import AppKit
import SwiftUI
import VoxaraCore

/// `Voxara --snapshot <dir>` renders every Command Center page and the overlay states to PNG files,
/// using synthetic sample data in a temporary folder. For visual review only; never touches real data.
@MainActor
enum SnapshotRenderer {
    static func run(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("voxara-snapshot-\(UUID().uuidString)")
        let model = AppModel(supportDirectory: temp)
        model.applySnapshotStatus()
        populate(model)

        let navigation = CommandCenterNavigation()
        for page in CommandCenterPage.allCases {
            navigation.page = page
            let view = CommandCenterView(model: model, navigation: navigation, openOnboarding: {})
            save(view, size: NSSize(width: 1040, height: 700), to: directory.appendingPathComponent("\(page.rawValue).png"))
        }
        let onboarding = OnboardingView(model: model, finish: {})
        save(onboarding, size: NSSize(width: 640, height: 520), to: directory.appendingPathComponent("onboarding.png"))
        try? FileManager.default.removeItem(at: temp)
        print("Snapshots written to \(directory.path)")
    }

    private static func populate(_ model: AppModel) {
        func timings(stt: Double, ai: Double, spoken: Double) -> PipelineTimings {
            var t = PipelineTimings()
            let start = Date().addingTimeInterval(-600)
            t.recordingStarted = start
            t.recordingEnded = start.addingTimeInterval(spoken)
            t.sttStarted = t.recordingEnded
            t.sttCompleted = t.recordingEnded?.addingTimeInterval(stt)
            t.processingStarted = t.sttCompleted
            t.processingCompleted = t.sttCompleted?.addingTimeInterval(ai)
            t.injected = t.processingCompleted?.addingTimeInterval(0.15)
            return t
        }
        let samples: [(HotkeyAction, String, String, String, String?, String, Double, Double, Double)] = [
            (.dictation, "so um I think we should ship the proposal tomorrow morning, actually no, Tuesday morning", "I think we should ship the proposal Tuesday morning.", "Mail", nil, "ollama", 0.21, 1.2, 6),
            (.prompt, "I need Claude Code to look through this project and see why the dashboard loading is slow and don't just randomly change stuff, investigate first, then fix it and run the tests",
             "Investigate why the dashboard loading is slow and then fix it.\n\nApproach:\n1. Identify the root cause from evidence rather than assuming it.\n2. Inspect the relevant code before changing anything.\n3. Make the fix.\n\nConstraints:\n- Keep the change as small as the problem allows and avoid unrelated modifications.\n\nValidation:\n- Verify the result with the project's own checks (tests, lint, type-check, build) where they apply.",
             "Terminal", "claude-code", "prompt-compiler", 0.27, 4.6, 14),
            (.dictation, "Провери dashboard компонента и виж дали API request-ите се изпълняват прекалено много пъти", "Провери dashboard компонента и виж дали API request-ите се изпълняват прекалено много пъти.", "Notion", nil, "rules", 0.19, 0.0, 5),
            (.dictation, "ъъ значи ще се видим в сряда в 14 часа", "Ще се видим в сряда в 14 часа.", "Messages", nil, "rules", 0.16, 0.0, 3),
        ]
        for (index, s) in samples.enumerated() {
            var record = DictationRecord(
                date: Date().addingTimeInterval(-Double(index) * 420), mode: s.0, rawTranscript: s.1, finalText: s.2,
                targetApp: s.3, targetBundleID: "x.\(s.3)", processor: s.5, promptProfile: s.4,
                promptPreset: s.0 == .prompt ? .structured : nil, inserted: true, timings: timings(stt: s.6, ai: s.7, spoken: s.8)
            )
            record.id = UUID()
            model.history.add(record)
        }
        for (id, name) in [("com.apple.Terminal", "Terminal"), ("notion.id", "Notion"), ("com.apple.MobileSMS", "Messages")] {
            model.appPreferences.noteUsage(bundleID: id, name: name)
        }
    }

    private static func save<V: View>(_ view: V, size: NSSize, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }
}
