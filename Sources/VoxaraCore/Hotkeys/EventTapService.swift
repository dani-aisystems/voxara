@preconcurrency import CoreFoundation
import CoreGraphics
import Foundation
import os

/// Marker stamped on events Voxara posts itself (e.g. the ⌘V paste) so the tap ignores them.
public let voxaraSyntheticEventTag: Int64 = 0x5654_5854 // "VTXT"

/// Global keyboard listener built on a CGEventTap running on its own high-priority thread,
/// so hotkey handling never waits on the main thread (which may be busy pasting or drawing).
public final class EventTapService: @unchecked Sendable {
    public typealias SignalHandler = @Sendable (HotkeySignal) -> Void

    private let log = VoxaraLog.logger("hotkeys")
    private let lock = NSLock()
    private var machine: HotkeyStateMachine
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private let onSignal: SignalHandler

    public init(bindings: [HotkeyAction: Shortcut], onSignal: @escaping SignalHandler) {
        self.machine = HotkeyStateMachine(bindings: bindings)
        self.onSignal = onSignal
    }

    public var isRunning: Bool {
        lock.withLock { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    }

    public func updateBindings(_ bindings: [HotkeyAction: Shortcut]) {
        lock.withLock {
            machine.bindings = bindings
            machine.reset()
        }
    }

    /// Call when the pipeline finished or aborted outside of a key release.
    public func resetState() {
        lock.withLock { machine.reset() }
    }

    /// Starts listening. Returns false if the tap could not be created (missing Accessibility permission).
    @discardableResult
    public func start() -> Bool {
        if lock.withLock({ tap != nil }) { return true }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            log.error("CGEvent.tapCreate failed; Accessibility permission is probably missing")
            return false
        }

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else { return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            // Health check: macOS can silently disable taps (timeouts, secure input).
            let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 5, 5, 0, 0) { [weak self] _ in
                self?.reenableIfNeeded()
            }
            CFRunLoopAddTimer(loop, timer, .commonModes)
            self.lock.withLock { self.runLoop = loop }
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "Voxara.EventTap"
        thread.qualityOfService = .userInteractive
        lock.withLock {
            self.tap = port
            self.thread = thread
        }
        thread.start()
        ready.wait()
        log.info("Event tap started")
        return true
    }

    public func stop() {
        let (port, loop) = lock.withLock { (tap, runLoop) }
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let loop { CFRunLoopStop(loop) }
        lock.withLock {
            tap = nil
            runLoop = nil
            thread = nil
        }
    }

    private func reenableIfNeeded() {
        guard let port = lock.withLock({ tap }) else { return }
        if !CGEvent.tapIsEnabled(tap: port) {
            log.warning("Event tap was disabled; re-enabling")
            CGEvent.tapEnable(tap: port, enable: true)
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reenableIfNeeded()
            lock.withLock { machine.reset() }
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp, .flagsChanged:
            break
        default:
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == voxaraSyntheticEventTag {
            return Unmanaged.passUnretained(event)
        }

        let kind: KeyEvent.Kind = switch type {
        case .keyDown: .keyDown(isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .keyUp: .keyUp
        default: .flagsChanged
        }
        let keyEvent = KeyEvent(
            kind: kind,
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags.rawValue,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        let decision = lock.withLock { machine.handle(keyEvent) }
        if let signal = decision.signal {
            onSignal(signal)
        }
        return decision.consume ? nil : Unmanaged.passUnretained(event)
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<EventTapService>.fromOpaque(refcon).takeUnretainedValue()
    return service.handle(type: type, event: event)
}
