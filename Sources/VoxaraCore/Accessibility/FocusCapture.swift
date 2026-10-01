import AppKit
import ApplicationServices

/// Snapshot of where the user's text cursor was when recording started.
public struct InsertionTarget: @unchecked Sendable {
    public let pid: pid_t
    public let bundleID: String?
    public let appName: String?
    /// Focused accessibility element, if the app exposes one.
    public let element: AXUIElement?
    public let role: String?

    /// Roles that definitely cannot accept typed text.
    static let nonTextRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXImage", "AXList", "AXOutline", "AXTable", "AXRow", "AXCell", "AXSlider",
        "AXToolbar", "AXMenuBar", "AXMenuItem", "AXDockItem", "AXWindow", "AXScrollBar",
    ]

    /// False only when we positively know the focus is not a text input. Web views and
    /// Electron apps often report generic roles (AXGroup, AXWebArea), so unknown counts as editable.
    public var mayAcceptText: Bool {
        guard let role else { return true }
        return !Self.nonTextRoles.contains(role)
    }
}

public enum FocusCapture {
    public static func current() -> InsertionTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)

        var focused: CFTypeRef?
        var element: AXUIElement?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            element = (focused as! AXUIElement)
        }
        return InsertionTarget(
            pid: app.processIdentifier,
            bundleID: app.bundleIdentifier,
            appName: app.localizedName,
            element: element,
            role: element.flatMap { AX.string($0, kAXRoleAttribute) }
        )
    }
}

enum AX {
    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func int(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }
}

public enum Permissions {
    public static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that deep-links to the Accessibility list.
    public static func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    public static func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
}
