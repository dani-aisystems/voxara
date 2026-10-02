import AppKit
import SwiftUI
import VoxaraCore

/// A window whose only job is to be a safe insertion target for tests: automated runs and test mode
/// route text here instead of into whatever app the user happens to be working in.
@MainActor
final class TestBenchWindow {
    static let shared = TestBenchWindow()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Voxara Test Bench"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: TestBenchView(model: model))
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // Put the caret in the text view so the very next dictation has somewhere to land.
        if let view = window?.contentView, let textView = Self.firstTextView(in: view) {
            window?.makeFirstResponder(textView)
        }
    }

    private static func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for sub in view.subviews { if let found = firstTextView(in: sub) { return found } }
        return nil
    }
}

private struct TestBenchView: View {
    let model: AppModel
    @LocalState private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: VX.Space.md) {
            HStack {
                Text("Insertion test bench").font(VX.Font.headline)
                Spacer()
                if model.settings.testMode { Chip(text: "TEST MODE", tint: VX.Palette.accent) }
            }
            Text("Click in the box, then hold \(model.settings.dictationShortcut.displayName.replacingOccurrences(of: "Hold ", with: "")) (dictation) or \(model.settings.promptShortcut.displayName.replacingOccurrences(of: "Hold ", with: "")) (prompt) and speak. Text lands here and nowhere else.")
                .font(VX.Font.caption).foregroundStyle(VX.Palette.textSecondary)
            TextEditor(text: $text)
                .font(VX.Font.body)
                .accessibilityIdentifier("voxara-test-bench-text")
                .padding(VX.Space.sm)
                .background(VX.Palette.surface, in: RoundedRectangle(cornerRadius: VX.Radius.md))
            HStack {
                Button("Clear") { text = "" }
                Spacer()
                Text("\(text.count) characters").font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
            }
        }
        .padding(VX.Space.lg)
        .background(VX.Palette.background)
    }
}
