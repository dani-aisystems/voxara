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
    /// Focused window title. Only read for browsers, where it identifies AI chat sites.
    public let windowTitle: String?

    /// Roles that definitely cannot accept typed text.
    static let nonTextRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXImage", "AXList", "AXOutline", "AXTable", "AXRow", "AXCell", "AXSlider",
        "AXToolbar", "AXMenuBar", "AXMenuItem", "AXDockItem", "AXWindow", "AXScrollBar",
    ]

    /// False only when we positively know the focus is not a text input. Web views and
    /// Electron apps often report generic roles (AXGroup, AXWebArea), so unknown counts as editable.
    /// Roles that are definitely text inputs.
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXWebArea"]

    /// True when the focused element is positively a text input (not merely 'unknown').
    public var isKnownTextInput: Bool {
        guard let role else { return false }
        return Self.textRoles.contains(role) && role != "AXWebArea"
    }

    public var mayAcceptText: Bool {
        guard let role else { return true }
        return !Self.nonTextRoles.contains(role)
    }
}

public enum FocusCapture {
    /// Processes already switched into "expose full accessibility tree" mode.
    nonisolated(unsafe) private static var enhanced = Set<pid_t>()
    private static let lock = NSLock()

    public static func current() -> InsertionTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)

        // Chromium and Electron apps (browsers, ChatGPT, Claude, Notion, VS Code…) expose their text fields to
        // Accessibility only when asked. Asking makes the focused field, its role and its value visible, so
        // Voxara can insert reliably and confirm the result.
        if AppTraits.isWebBased(pid: pid, bundleID: app.bundleIdentifier) { enableFullAccessibility(appElement, pid: pid) }

        var focused: CFTypeRef?
        var element: AXUIElement?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            element = (focused as! AXUIElement)
        } else {
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.25)
            if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
               let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                element = (focused as! AXUIElement)
            }
        }

        var title: String?
        if let bundleID = app.bundleIdentifier, AppCatalog.browsers.contains(bundleID) {
            var window: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window) == .success,
               let window, CFGetTypeID(window) == AXUIElementGetTypeID() {
                title = AX.string(window as! AXUIElement, kAXTitleAttribute)
            }
        }
        return InsertionTarget(
            pid: pid,
            bundleID: app.bundleIdentifier,
            appName: app.localizedName,
            element: element,
            role: element.flatMap { AX.string($0, kAXRoleAttribute) },
            windowTitle: title
        )
    }

    private static func enableFullAccessibility(_ appElement: AXUIElement, pid: pid_t) {
        let alreadyEnabled = lock.withLock { !enhanced.insert(pid).inserted }
        guard !alreadyEnabled else { return }
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
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
