import Carbon.HIToolbox
import Foundation

/// Finds the physical key that produces "v" for the ⌘V paste shortcut.
///
/// macOS resolves ⌘-shortcuts through the ASCII-capable layout (e.g. "ABC" while the
/// Bulgarian layout is active), so we look the character up there. This keeps ⌘V working
/// with Cyrillic layouts and moves it correctly for Dvorak/Colemak users.
public enum KeyCodeResolver {
    public static var pasteKeyCode: CGKeyCode {
        keyCode(producing: "v") ?? CGKeyCode(kVK_ANSI_V)
    }

    static func keyCode(producing character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let target = String(character).lowercased()
        let found: CGKeyCode? = data.withUnsafeBytes { buffer in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in 0..<128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDown), 0,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState, chars.count, &length, &chars
                )
                if status == noErr, length > 0, String(utf16CodeUnits: chars, count: length).lowercased() == target {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
        return found
    }
}
