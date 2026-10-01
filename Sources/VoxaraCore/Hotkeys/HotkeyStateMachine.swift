import Foundation

/// A keyboard event reduced to what the hotkey logic needs. Pure data so the state
/// machine can be unit-tested without CGEvents.
public struct KeyEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case keyDown(isRepeat: Bool)
        case keyUp
        case flagsChanged
    }

    public var kind: Kind
    public var keyCode: UInt16
    /// Raw `CGEventFlags` bits (device-dependent bits identify left/right modifiers).
    public var flags: UInt64
    public var timestamp: TimeInterval

    public init(kind: Kind, keyCode: UInt16, flags: UInt64, timestamp: TimeInterval) {
        self.kind = kind
        self.keyCode = keyCode
        self.flags = flags
        self.timestamp = timestamp
    }
}

public enum HotkeySignal: Sendable, Equatable {
    case start(HotkeyAction)
    case stop(HotkeyAction)
    /// Recording should be discarded (shortcut interrupted, accidental tap, or Esc).
    case cancel(HotkeyAction)
}

public struct HotkeyDecision: Sendable, Equatable {
    public var signal: HotkeySignal?
    /// Whether the event should be swallowed instead of reaching the focused app.
    public var consume: Bool

    static let pass = HotkeyDecision(signal: nil, consume: false)
}

/// Push-to-talk logic for modifier-only and combo shortcuts.
///
/// - Recording starts immediately on press so the first words are never lost.
/// - Pressing any other key while a lone modifier is held cancels silently, so normal
///   shortcuts such as Right ⌘ + C keep working.
/// - Releases shorter than `minimumHold` are treated as accidental taps.
/// - Esc cancels an active recording and is swallowed so it does not reach the app.
public struct HotkeyStateMachine: Sendable {
    public var bindings: [HotkeyAction: Shortcut]
    public var minimumHold: TimeInterval

    private enum State: Sendable, Equatable {
        case idle
        case holding(HotkeyAction, since: TimeInterval)
        /// After a cancel, wait until every bound key is released before re-arming.
        case waitingForRelease
    }

    private var state: State = .idle

    public init(bindings: [HotkeyAction: Shortcut], minimumHold: TimeInterval = 0.25) {
        self.bindings = bindings
        self.minimumHold = minimumHold
    }

    public var isActive: Bool {
        if case .holding = state { return true }
        return false
    }

    /// Forces the machine back to idle (e.g. after the pipeline aborted on its own).
    public mutating func reset() {
        state = .idle
    }

    public mutating func handle(_ event: KeyEvent) -> HotkeyDecision {
        switch state {
        case .idle:
            return handleIdle(event)
        case .holding(let action, let since):
            return handleHolding(event, action: action, since: since)
        case .waitingForRelease:
            if case .flagsChanged = event.kind, ModifierKey.held(in: event.flags).isEmpty {
                state = .idle
            }
            if case .keyUp = event.kind { state = .idle }
            return .pass
        }
    }

    private mutating func handleIdle(_ event: KeyEvent) -> HotkeyDecision {
        let held = ModifierKey.held(in: event.flags)
        for (action, shortcut) in bindings.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            switch shortcut {
            case .modifier(let key):
                // Arm only when exactly this modifier went down on its own.
                if event.kind == .flagsChanged, event.keyCode == key.rawValue, held == [key] {
                    state = .holding(action, since: event.timestamp)
                    return HotkeyDecision(signal: .start(action), consume: false)
                }
            case .combo(let keyCode, let modifiers):
                if case .keyDown(let isRepeat) = event.kind, !isRepeat, event.keyCode == keyCode,
                   Self.matches(held: held, required: modifiers) {
                    state = .holding(action, since: event.timestamp)
                    return HotkeyDecision(signal: .start(action), consume: true)
                }
            }
        }
        return .pass
    }

    private mutating func handleHolding(_ event: KeyEvent, action: HotkeyAction, since: TimeInterval) -> HotkeyDecision {
        guard let shortcut = bindings[action] else {
            state = .idle
            return HotkeyDecision(signal: .cancel(action), consume: false)
        }

        if case .keyDown = event.kind, event.keyCode == KeyNames.escape {
            state = .waitingForRelease
            return HotkeyDecision(signal: .cancel(action), consume: true)
        }

        switch shortcut {
        case .modifier(let key):
            switch event.kind {
            case .keyDown:
                // Another key while holding: the user is typing a shortcut, not dictating.
                state = .waitingForRelease
                return HotkeyDecision(signal: .cancel(action), consume: false)
            case .keyUp:
                return .pass
            case .flagsChanged:
                let held = ModifierKey.held(in: event.flags)
                if !held.contains(key) {
                    state = .idle
                    let signal: HotkeySignal = event.timestamp - since < minimumHold ? .cancel(action) : .stop(action)
                    return HotkeyDecision(signal: signal, consume: false)
                }
                if held != [key] {
                    // Another modifier joined the hold (e.g. ⌘⇧ shortcut in progress).
                    state = .waitingForRelease
                    return HotkeyDecision(signal: .cancel(action), consume: false)
                }
                return .pass
            }
        case .combo(let keyCode, _):
            switch event.kind {
            case .keyDown:
                // Swallow auto-repeat of the shortcut key itself.
                return event.keyCode == keyCode ? HotkeyDecision(signal: nil, consume: true) : .pass
            case .keyUp where event.keyCode == keyCode:
                state = .idle
                let signal: HotkeySignal = event.timestamp - since < minimumHold ? .cancel(action) : .stop(action)
                return HotkeyDecision(signal: signal, consume: true)
            default:
                return .pass
            }
        }
    }

    /// Combo modifiers match by side-agnostic family when the binding names only one side.
    static func matches(held: Set<ModifierKey>, required: Set<ModifierKey>) -> Bool {
        func family(_ key: ModifierKey) -> Int {
            switch key {
            case .leftCommand, .rightCommand: 0
            case .leftShift, .rightShift: 1
            case .leftOption, .rightOption: 2
            case .leftControl, .rightControl: 3
            case .function: 4
            }
        }
        let heldFamilies = Set(held.filter { $0 != .function }.map(family))
        let requiredFamilies = Set(required.filter { $0 != .function }.map(family))
        return heldFamilies == requiredFamilies
    }
}
