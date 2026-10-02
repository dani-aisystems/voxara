import AppKit
import VoxaraCore

/// Development-only hook for end-to-end tests without speaking. Enabled with
/// `defaults write com.daniel.voicetext EnableDebugCommands -bool true`.
///
/// Trigger with a distributed notification named `com.daniel.voicetext.debug` and
/// userInfo `{command: "dictate-file", path: "/abs/file.wav", mode: "dictation"|"prompt", expectBundleID: "com.apple.TextEdit"}`.
/// The run is refused unless the frontmost app has exactly that bundle identifier.
@MainActor
final class DebugCommandListener {
    private let pipeline: DictationPipeline

    init(pipeline: DictationPipeline) {
        self.pipeline = pipeline
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(received(_:)),
            name: Notification.Name("com.daniel.voicetext.debug"), object: nil
        )
    }

    @objc private func received(_ note: Notification) {
        guard let info = note.userInfo, info["command"] as? String == "dictate-file",
              let path = info["path"] as? String,
              let expected = info["expectBundleID"] as? String else { return }
        let mode = HotkeyAction(rawValue: info["mode"] as? String ?? "dictation") ?? .dictation
        pipeline.runFile(URL(fileURLWithPath: path), action: mode, expectBundleID: expected)
    }
}
