import AppKit
import os
import VoiceTextCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.daniel.voicetext", category: "app")
    private var pipeline: DictationPipeline!
    private var hotkeys: EventTapService!
    private var statusMenu: StatusMenuController!
    private var debugListener: DebugCommandListener?
    private let transcriber = ParakeetTranscriber(variant: .v3)
    /// Keeps the hotkey listener responsive: no App Nap, no automatic termination.
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Listening for dictation hotkeys")
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Listening for dictation hotkeys"
        )
        pipeline = DictationPipeline(
            recorder: AudioRecorder(),
            transcriber: transcriber,
            injector: TextInjector(),
            processor: PassthroughProcessor()
        )
        statusMenu = StatusMenuController(pipeline: pipeline)
        pipeline.onStateChange = { [weak self] state in
            self?.statusMenu.update(state: state)
            if case .listening = state { return }
            if case .transcribing = state { return }
            if case .processing = state { return }
            self?.hotkeys.resetState()
        }

        hotkeys = EventTapService(bindings: [.dictation: .defaultDictation, .prompt: .defaultPrompt]) { [weak self] signal in
            Task { @MainActor in self?.pipeline.handle(signal) }
        }
        startHotkeysWhenTrusted()
        Task { await prepareMicrophone() }
        Task { await loadModel() }

        if UserDefaults.standard.bool(forKey: "EnableDebugCommands") {
            debugListener = DebugCommandListener(pipeline: pipeline)
        }
    }

    private func startHotkeysWhenTrusted() {
        if Permissions.accessibilityGranted, hotkeys.start() {
            statusMenu.setPermissionWarning(nil)
            return
        }
        Permissions.requestAccessibility()
        statusMenu.setPermissionWarning("Grant Accessibility access to enable hotkeys")
        // Poll until the user grants access in System Settings; no relaunch needed.
        Task { [weak self] in
            while !Permissions.accessibilityGranted {
                try? await Task.sleep(for: .seconds(1))
            }
            guard let self, self.hotkeys.start() else { return }
            self.statusMenu.setPermissionWarning(nil)
        }
    }

    private func prepareMicrophone() async {
        switch AudioRecorder.permission {
        case .authorized: return
        case .notDetermined: _ = await AudioRecorder.requestPermission()
        default: statusMenu.setPermissionWarning("Microphone access is denied")
        }
    }

    private func loadModel() async {
        statusMenu.setModelStatus("Loading speech model…")
        do {
            let menu = statusMenu!
            try await transcriber.prepare { progress in
                Task { @MainActor in
                    menu.setModelStatus("Downloading speech model… \(Int(progress * 100))%")
                }
            }
            statusMenu.setModelStatus(nil)
            log.info("Speech model ready")
        } catch {
            statusMenu.setModelStatus("Speech model failed to load: \(error.localizedDescription)")
            log.error("Model load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
