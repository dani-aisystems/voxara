import AppKit
import ApplicationServices
import os

public enum InsertionMethod: String, Codable, CaseIterable, Sendable {
    /// Clipboard + ⌘V with full clipboard restore. Works in practically every app.
    case paste
    /// Set the focused element's selected text via Accessibility; falls back to paste.
    case accessibility

    public var displayName: String {
        switch self {
        case .paste: "Paste (recommended)"
        case .accessibility: "Accessibility API, then paste"
        }
    }
}

public enum InsertionOutcome: Sendable, Equatable {
    /// Text was inserted (verified, or the target cannot be inspected but the paste was delivered).
    case inserted(verified: Bool)
    /// Could not insert; the text was left on the clipboard for a manual ⌘V.
    case copiedToClipboard(reason: String)
}

/// Delivers text into the app the user was typing in.
@MainActor
public final class TextInjector {
    private let log = VoxaraLog.logger("insertion")
    public var method: InsertionMethod = .paste
    /// Base delay before restoring the clipboard; browsers/Electron get extra time.
    public var restoreDelay: TimeInterval = 0.35

    public init() {}

    public func insert(_ text: String, into target: InsertionTarget?) async -> InsertionOutcome {
        guard !text.isEmpty else { return .inserted(verified: true) }
        guard Permissions.accessibilityGranted else {
            NSPasteboard.general.writePlainText(text)
            return .copiedToClipboard(reason: "Accessibility permission is missing")
        }
        if let target, !target.mayAcceptText {
            NSPasteboard.general.writePlainText(text)
            return .copiedToClipboard(reason: "The focused element is not a text field")
        }
        if let target { await reactivate(target) }

        if method == .accessibility, let element = target?.element, insertViaAccessibility(text, element: element) {
            return .inserted(verified: true)
        }
        return await paste(text, target: target)
    }

    // MARK: - Paste

    private func paste(_ text: String, target: InsertionTarget?) async -> InsertionOutcome {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(pasteboard)
        let before = target?.element.flatMap(Self.characterCount)

        let ourChange = pasteboard.writeTransientText(text)
        // Let the pasteboard server publish the new contents before the target reads them.
        try? await Task.sleep(for: .milliseconds(20))
        postCommandV()

        try? await Task.sleep(for: .seconds(restoreDelay + extraDelay(for: target)))

        // Verification is only meaningful for elements that expose their character count.
        var verified = false
        if let element = target?.element, let before, let after = Self.characterCount(element) {
            if after == before {
                log.warning("Paste not detected in \(target?.bundleID ?? "?", privacy: .public); leaving text on clipboard")
                if pasteboard.changeCount == ourChange { pasteboard.writePlainText(text) }
                return .copiedToClipboard(reason: "The app did not accept the pasted text")
            }
            verified = true
        }

        if pasteboard.changeCount == ourChange {
            snapshot.restore(to: pasteboard)
        } else {
            log.info("Clipboard changed during paste; not restoring")
        }
        return .inserted(verified: verified)
    }

    private func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = KeyCodeResolver.pasteKeyCode
        let commandKey: CGKeyCode = 55
        let events = [
            CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: true),
            CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false),
            CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: false),
        ]
        for (index, event) in events.enumerated() {
            guard let event else { continue }
            // Electron/Chromium need the ⌘ flag on the ⌘-down event itself; clear it on release.
            event.flags = index < 3 ? .maskCommand : []
            event.setIntegerValueField(.eventSourceUserData, value: voxaraSyntheticEventTag)
            event.post(tap: .cghidEventTap)
        }
    }

    private func extraDelay(for target: InsertionTarget?) -> TimeInterval {
        guard let target else { return 0.15 }
        return AppTraits.isWebBased(pid: target.pid, bundleID: target.bundleID) ? 0.3 : 0
    }

    // MARK: - Accessibility insertion

    private func insertViaAccessibility(_ text: String, element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        let before = Self.characterCount(element)
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success else {
            return false
        }
        // Some apps report success without changing anything; confirm when possible.
        if let before, let after = Self.characterCount(element) { return after != before }
        return true
    }

    private static func characterCount(_ element: AXUIElement) -> Int? {
        AX.int(element, kAXNumberOfCharactersAttribute)
            ?? AX.string(element, kAXValueAttribute).map { $0.utf16.count }
    }

    // MARK: - Focus

    /// Brings the original app back to the front if the user switched away while processing.
    private func reactivate(_ target: InsertionTarget) async {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != target.pid,
              let app = NSRunningApplication(processIdentifier: target.pid) else { return }
        NSApp.yieldActivation(to: app)
        app.activate()
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid { break }
            try? await Task.sleep(for: .milliseconds(15))
        }
        if let element = target.element {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        try? await Task.sleep(for: .milliseconds(60))
    }
}

/// Facts about target apps that affect insertion timing.
public enum AppTraits {
    static let browserBundleIDs: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "org.mozilla.firefox",
        "company.thebrowser.Browser", "com.microsoft.edgemac", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    public static func isWebBased(pid: pid_t, bundleID: String?) -> Bool {
        if let bundleID, browserBundleIDs.contains(bundleID) { return true }
        guard let url = NSRunningApplication(processIdentifier: pid)?.bundleURL else { return false }
        let electron = url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: electron.path)
    }
}
