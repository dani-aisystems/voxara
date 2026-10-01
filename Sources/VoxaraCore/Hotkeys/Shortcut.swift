import Foundation

/// The two things a hotkey can trigger.
public enum HotkeyAction: String, Codable, CaseIterable, Sendable {
    case dictation
    case prompt
}

/// A physical modifier key, identified by its virtual key code. Left/right are distinct.
public enum ModifierKey: UInt16, Codable, CaseIterable, Sendable {
    case leftCommand = 55
    case rightCommand = 54
    case leftShift = 56
    case rightShift = 60
    case leftOption = 58
    case rightOption = 61
    case leftControl = 59
    case rightControl = 62
    case function = 63

    /// Device-dependent bit in `CGEventFlags` (IOKit `NX_DEVICE*KEYMASK`, `NX_SECONDARYFNMASK`).
    public var deviceFlag: UInt64 {
        switch self {
        case .leftControl: 0x0000_0001
        case .leftShift: 0x0000_0002
        case .rightShift: 0x0000_0004
        case .leftCommand: 0x0000_0008
        case .rightCommand: 0x0000_0010
        case .leftOption: 0x0000_0020
        case .rightOption: 0x0000_0040
        case .rightControl: 0x0000_2000
        case .function: 0x0080_0000
        }
    }

    public var displayName: String {
        switch self {
        case .leftCommand: "Left ⌘"
        case .rightCommand: "Right ⌘"
        case .leftShift: "Left ⇧"
        case .rightShift: "Right ⇧"
        case .leftOption: "Left ⌥"
        case .rightOption: "Right ⌥"
        case .leftControl: "Left ⌃"
        case .rightControl: "Right ⌃"
        case .function: "fn"
        }
    }

    /// Modifier keys currently held according to the device-dependent flag bits.
    public static func held(in flags: UInt64) -> Set<ModifierKey> {
        Set(allCases.filter { flags & $0.deviceFlag != 0 })
    }
}

/// A user-configurable shortcut: either a lone modifier held down, or a key plus modifiers.
public enum Shortcut: Codable, Hashable, Sendable {
    case modifier(ModifierKey)
    case combo(keyCode: UInt16, modifiers: Set<ModifierKey>)

    public static let defaultDictation = Shortcut.modifier(.rightOption)
    public static let defaultPrompt = Shortcut.modifier(.rightCommand)

    public var displayName: String {
        switch self {
        case .modifier(let key):
            return "Hold \(key.displayName)"
        case .combo(let keyCode, let modifiers):
            let order: [ModifierKey] = [.leftControl, .rightControl, .leftOption, .rightOption, .leftShift, .rightShift, .leftCommand, .rightCommand, .function]
            let mods = order.filter(modifiers.contains).map(\.displayName).joined(separator: " ")
            let key = KeyNames.name(for: keyCode)
            return mods.isEmpty ? key : "\(mods) \(key)"
        }
    }
}

public enum KeyNames {
    public static let escape: UInt16 = 53

    static let names: [UInt16: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
        38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
        15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
    ]

    public static func name(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}
