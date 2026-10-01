import Foundation
import Testing
@testable import VoxaraCore

@Suite struct HotkeyStateMachineTests {
    private let rightOption = ModifierKey.rightOption
    private let rightCommand = ModifierKey.rightCommand
    private let optionMask: UInt64 = 0x80000
    private let commandMask: UInt64 = 0x100000

    private func machine() -> HotkeyStateMachine {
        HotkeyStateMachine(bindings: [.dictation: .defaultDictation, .prompt: .defaultPrompt])
    }

    private func flags(_ key: ModifierKey, mask: UInt64) -> UInt64 { mask | key.deviceFlag }

    private func press(_ key: ModifierKey, mask: UInt64, at t: TimeInterval) -> KeyEvent {
        KeyEvent(kind: .flagsChanged, keyCode: key.rawValue, flags: flags(key, mask: mask), timestamp: t)
    }

    private func release(_ key: ModifierKey, at t: TimeInterval) -> KeyEvent {
        KeyEvent(kind: .flagsChanged, keyCode: key.rawValue, flags: 0, timestamp: t)
    }

    private func key(_ code: UInt16, down: Bool, flags: UInt64, at t: TimeInterval) -> KeyEvent {
        KeyEvent(kind: down ? .keyDown(isRepeat: false) : .keyUp, keyCode: code, flags: flags, timestamp: t)
    }

    @Test func holdRightOptionStartsAndStopsDictation() {
        var m = machine()
        #expect(m.handle(press(rightOption, mask: optionMask, at: 0)).signal == .start(.dictation))
        #expect(m.isActive)
        #expect(m.handle(release(rightOption, at: 1.0)).signal == .stop(.dictation))
        #expect(!m.isActive)
    }

    @Test func holdRightCommandStartsPromptMode() {
        var m = machine()
        #expect(m.handle(press(rightCommand, mask: commandMask, at: 0)).signal == .start(.prompt))
        #expect(m.handle(release(rightCommand, at: 2.0)).signal == .stop(.prompt))
    }

    @Test func leftOptionDoesNotTrigger() {
        var m = machine()
        let event = press(.leftOption, mask: optionMask, at: 0)
        #expect(m.handle(event).signal == nil)
    }

    @Test func shortTapIsCancelledAsAccidental() {
        var m = machine()
        _ = m.handle(press(rightOption, mask: optionMask, at: 0))
        #expect(m.handle(release(rightOption, at: 0.1)).signal == .cancel(.dictation))
    }

    @Test func otherKeyDuringHoldCancelsSoShortcutsStillWork() {
        var m = machine()
        _ = m.handle(press(rightCommand, mask: commandMask, at: 0))
        // Right ⌘ + C
        let decision = m.handle(key(8, down: true, flags: flags(rightCommand, mask: commandMask), at: 0.4))
        #expect(decision.signal == .cancel(.prompt))
        #expect(!decision.consume)
        // Releasing afterwards must not produce a stop, and re-arms once all modifiers are up.
        #expect(m.handle(release(rightCommand, at: 0.8)).signal == nil)
        #expect(m.handle(press(rightOption, mask: optionMask, at: 1.0)).signal == .start(.dictation))
    }

    @Test func additionalModifierCancelsHold() {
        var m = machine()
        _ = m.handle(press(rightOption, mask: optionMask, at: 0))
        let both = KeyEvent(kind: .flagsChanged, keyCode: ModifierKey.leftShift.rawValue,
                            flags: optionMask | 0x20000 | rightOption.deviceFlag | ModifierKey.leftShift.deviceFlag, timestamp: 0.5)
        #expect(m.handle(both).signal == .cancel(.dictation))
    }

    @Test func escapeCancelsAndIsConsumed() {
        var m = machine()
        _ = m.handle(press(rightOption, mask: optionMask, at: 0))
        let decision = m.handle(key(KeyNames.escape, down: true, flags: flags(rightOption, mask: optionMask), at: 1))
        #expect(decision.signal == .cancel(.dictation))
        #expect(decision.consume)
    }

    @Test func ignoresPressWhenAnotherModifierAlreadyHeld() {
        var m = machine()
        let both = KeyEvent(kind: .flagsChanged, keyCode: rightOption.rawValue,
                            flags: optionMask | rightOption.deviceFlag | ModifierKey.leftControl.deviceFlag | 0x40000, timestamp: 0)
        #expect(m.handle(both).signal == nil)
    }

    @Test func comboShortcutHoldsAndConsumesKey() {
        var m = HotkeyStateMachine(bindings: [.dictation: .combo(keyCode: 49, modifiers: [.leftControl, .leftOption])])
        let mods: UInt64 = ModifierKey.leftControl.deviceFlag | ModifierKey.leftOption.deviceFlag
        let down = m.handle(key(49, down: true, flags: mods, at: 0))
        #expect(down.signal == .start(.dictation))
        #expect(down.consume)
        let up = m.handle(key(49, down: false, flags: mods, at: 1))
        #expect(up.signal == .stop(.dictation))
    }

    @Test func resetReturnsToIdle() {
        var m = machine()
        _ = m.handle(press(rightOption, mask: optionMask, at: 0))
        m.reset()
        #expect(!m.isActive)
        #expect(m.handle(press(rightOption, mask: optionMask, at: 2)).signal == .start(.dictation))
    }
}
