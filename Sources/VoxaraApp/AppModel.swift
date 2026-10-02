import AppKit
import Observation
import ServiceManagement
import SwiftUI
import VoxaraCore

/// Single source of truth for the running app: settings, stores, the pipeline and live status.
/// Views read from it; changing `settings` persists and rebuilds the processing chain.
@MainActor
@Observable
final class AppModel {
    // MARK: Persistent state
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            SettingsPersistence.save(settings)
            applySettings(old: oldValue)
        }
    }
    let history: HistoryStore
    let vocabulary: VocabularyStore
    let appPreferences: AppPreferencesStore
    private(set) var profiles: ProfileStore

    // MARK: Live status
    private(set) var pipelineState: PipelineState = .idle
    /// Recent microphone levels (0…1), newest last, for the overlay meter.
    private(set) var levels: [Float] = Array(repeating: 0, count: 9)
    private(set) var speechModelStatus: ModelStatus = .loading(progress: nil)
    private(set) var ollama: OllamaStatus = .checking
    private(set) var microphoneAuthorized = AudioRecorder.permission == .authorized
    private(set) var accessibilityGranted = Permissions.accessibilityGranted
    private(set) var hotkeysRunning = false

    enum ModelStatus: Equatable {
        case loading(progress: Double?)
        case ready
        case failed(String)
    }

    enum OllamaStatus: Equatable {
        case checking
        case unavailable(String)
        /// Service is up. `installed` lists model names; `modelReady` tells whether the selected one is present.
        case running(installed: [String], modelReady: Bool)
    }

    // MARK: Engine
    let pipeline: DictationPipeline
    let transcriber = ParakeetTranscriber(variant: .v3)
    private let injector: TextInjector
    private var hotkeys: EventTapService?
    private var statusTask: Task<Void, Never>?
    private var overlay: OverlayController?

    // MARK: Test bench
    /// Bundle identifier of this app; the only insertion target allowed in test mode.
    let ownBundleID = Bundle.main.bundleIdentifier ?? "com.daniel.voicetext"

    /// `supportDirectory` overrides where stores live (used by `--snapshot`, which must never touch real data).
    init(supportDirectory: URL? = nil) {
        let loaded = supportDirectory == nil ? SettingsPersistence.load() : AppSettings()
        settings = loaded
        if let dir = supportDirectory {
            history = HistoryStore(fileURL: dir.appendingPathComponent("history.json"))
            vocabulary = VocabularyStore(fileURL: dir.appendingPathComponent("vocabulary.json"))
            appPreferences = AppPreferencesStore(fileURL: dir.appendingPathComponent("applications.json"))
            profiles = (try? ProfileStore.load(userDirectory: nil)) ?? ProfileStore.fallback
        } else {
            history = HistoryStore()
            vocabulary = VocabularyStore()
            appPreferences = AppPreferencesStore()
            profiles = (try? ProfileStore.load()) ?? ProfileStore.fallback
        }
        let injector = TextInjector()
        injector.method = loaded.insertionMethod
        self.injector = injector
        pipeline = DictationPipeline(recorder: AudioRecorder(), transcriber: transcriber, injector: injector, processor: PassthroughProcessor())
    }

    // MARK: Lifecycle

    func start() {
        ProcessInfo.processInfo.disableAutomaticTermination("Listening for dictation hotkeys")
        keepAlive = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Listening for dictation hotkeys")

        pipeline.contextResolver = { [weak self] action, target in
            guard let self else { return ResolvedContext(mode: action, promptProfile: "generic", promptPreset: .structured, cleanup: .smart, source: "Default") }
            appPreferences.noteUsage(bundleID: target?.bundleID, name: target?.appName)
            return ResolvedContext.resolve(
                action: action, bundleID: target?.bundleID, windowTitle: target?.windowTitle,
                settings: settings, preference: appPreferences.preference(for: target?.bundleID)
            )
        }
        pipeline.insertionGuard = { [weak self] target in
            guard let self, settings.testMode else { return nil }
            return target?.bundleID == ownBundleID ? nil : "Test mode is on — text was not inserted into other apps"
        }
        pipeline.onStateChange = { [weak self] state in self?.handle(state: state) }
        pipeline.onLevel = { [weak self] level in self?.push(level: level) }
        pipeline.onRecord = { [weak self] record in self?.record(record) }

        overlay = OverlayController(model: self)
        rebuildProcessor()
        startHotkeys()
        SystemBulgarianLexicon.warmUp()

        Task { await prepareMicrophone() }
        Task { await loadSpeechModel() }
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStatus()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    private var keepAlive: NSObjectProtocol?

    // MARK: Settings application

    private func applySettings(old: AppSettings) {
        pipeline.language = settings.language
        pipeline.outputLanguage = settings.promptOutputLanguage
        if old.insertionMethod != settings.insertionMethod { injectorMethod(settings.insertionMethod) }
        if old.dictationShortcut != settings.dictationShortcut || old.promptShortcut != settings.promptShortcut {
            hotkeys?.updateBindings(settings.hotkeyBindings)
        }
        if old.intelligenceModel != settings.intelligenceModel || old.ollamaURL != settings.ollamaURL
            || old.vocabularyEnabled != settings.vocabularyEnabled {
            rebuildProcessor()
            Task { await refreshStatus(); await warmUpModel() }
        }
        if old.testMode != settings.testMode {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func injectorMethod(_ method: InsertionMethod) {
        injector.method = method
    }

    /// Rebuilds the processing chain after the provider, model or vocabulary changed.
    func rebuildProcessor() {
        let provider: any AIProvider = OllamaProvider(
            baseURL: URL(string: settings.ollamaURL) ?? URL(string: "http://127.0.0.1:11434")!,
            model: settings.intelligenceModel
        )
        let repairer = settings.vocabularyEnabled ? TermRepairer(entries: vocabulary.entries) : nil
        pipeline.processor = ProcessingRouter(
            refiner: DictationRefiner(provider: provider),
            compiler: PromptCompiler(provider: provider, profiles: profiles),
            repairer: repairer
        )
        pipeline.language = settings.language
        pipeline.outputLanguage = settings.promptOutputLanguage
    }

    /// Call after the vocabulary changed so the next dictation uses it.
    func vocabularyChanged() { rebuildProcessor() }

    func reloadProfiles() {
        if let fresh = try? ProfileStore.load() { profiles = fresh }
        rebuildProcessor()
    }

    // MARK: Hotkeys & permissions

    private func startHotkeys() {
        let service = EventTapService(bindings: settings.hotkeyBindings) { [weak self] signal in
            Task { @MainActor in self?.pipeline.handle(signal) }
        }
        hotkeys = service
        if Permissions.accessibilityGranted, service.start() {
            hotkeysRunning = true
            return
        }
        Permissions.requestAccessibility()
        Task { [weak self] in
            while !Permissions.accessibilityGranted { try? await Task.sleep(for: .seconds(1)) }
            guard let self else { return }
            self.hotkeysRunning = service.start()
            self.accessibilityGranted = true
        }
    }

    func prepareMicrophone() async {
        switch AudioRecorder.permission {
        case .notDetermined: microphoneAuthorized = await AudioRecorder.requestPermission()
        case .authorized: microphoneAuthorized = true
        default: microphoneAuthorized = false
        }
    }

    // MARK: Models

    func loadSpeechModel() async {
        speechModelStatus = .loading(progress: nil)
        do {
            try await transcriber.prepare { [weak self] progress in
                Task { @MainActor in self?.speechModelStatus = .loading(progress: progress) }
            }
            speechModelStatus = .ready
        } catch {
            speechModelStatus = .failed(error.localizedDescription)
        }
    }

    func refreshStatus() async {
        microphoneAuthorized = AudioRecorder.permission == .authorized
        accessibilityGranted = Permissions.accessibilityGranted
        hotkeysRunning = hotkeys?.isRunning ?? false

        let provider = OllamaProvider(baseURL: URL(string: settings.ollamaURL) ?? URL(string: "http://127.0.0.1:11434")!,
                                      model: settings.intelligenceModel)
        do {
            let installed = try await provider.installedModels()
            let wanted = settings.intelligenceModel.contains(":") ? settings.intelligenceModel : settings.intelligenceModel + ":latest"
            let wasReady: Bool = { if case .running(_, true) = ollama { true } else { false } }()
            let ready = installed.contains(wanted)
            ollama = .running(installed: installed, modelReady: ready)
            if ready, !wasReady { await warmUpModelIfNeeded() }
        } catch {
            ollama = .unavailable("Ollama is not running")
        }
    }

    private var lastWarmUp = Date.distantPast

    /// Cheap when the model is already loaded (a one-token request); throttled so it never spams Ollama.
    func warmUpModelIfNeeded() async {
        guard Date().timeIntervalSince(lastWarmUp) > 20 else { return }
        lastWarmUp = Date()
        await warmUpModel()
    }

    func warmUpModel() async {
        guard case .running(_, true) = ollama else { return }
        let provider = OllamaProvider(baseURL: URL(string: settings.ollamaURL) ?? URL(string: "http://127.0.0.1:11434")!,
                                      model: settings.intelligenceModel)
        await provider.warmUp()
    }

    // MARK: Pipeline callbacks

    private func handle(state: PipelineState) {
        pipelineState = state
        switch state {
        case .listening:
            levels = Array(repeating: 0, count: levels.count)
            // Load the local model while the user is still speaking, so cleanup never waits on a cold start.
            Task { await warmUpModelIfNeeded() }
        case .idle, .done, .failed: hotkeys?.resetState()
        default: break
        }
        overlay?.update(state: state)
        playSound(for: state)
    }

    private func push(level: Float) {
        // Speech RMS is small; scale to a perceptual 0…1 range.
        let scaled = min(1, max(0, level * 9).squareRoot())
        levels.removeFirst()
        levels.append(scaled)
    }

    private func record(_ record: DictationRecord) {
        if settings.saveHistory { history.add(record) }
    }

    // MARK: Actions

    /// Fills in plausible status for offscreen snapshots only.
    func applySnapshotStatus() {
        speechModelStatus = .ready
        ollama = .running(installed: [settings.intelligenceModel], modelReady: true)
        microphoneAuthorized = true
        accessibilityGranted = true
        hotkeysRunning = true
    }

    func setMode(profile: String) { settings.promptProfile = profile }

    /// Suspends the global shortcuts, e.g. while the user is recording a new shortcut.
    func pauseHotkeys() {
        hotkeys?.stop()
        hotkeysRunning = false
    }

    func resumeHotkeys() {
        if Permissions.accessibilityGranted { hotkeysRunning = hotkeys?.start() ?? false }
    }

    /// Puts previously generated text back into an app (History → Insert again). Honours test mode.
    func reinsert(_ text: String, into app: NSRunningApplication) {
        Task {
            NSApp.yieldActivation(to: app)
            app.activate()
            try? await Task.sleep(for: .milliseconds(350))
            let target = FocusCapture.current()
            if settings.testMode, target?.bundleID != ownBundleID {
                NSPasteboard.general.writePlainText(text)
                return
            }
            let outcome = await injector.insert(text, into: target)
            if case .copiedToClipboard = outcome { NSSound.beep() }
        }
    }

    private func playSound(for state: PipelineState) {
        guard settings.playSounds else { return }
        switch state {
        case .listening: NSSound(named: "Tink")?.play()
        case .done: NSSound(named: "Pop")?.play()
        case .failed: NSSound(named: "Basso")?.play()
        default: break
        }
    }

    func copyLastResult() {
        guard let text = pipeline.lastResult else { return }
        NSPasteboard.general.writePlainText(text)
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSSound.beep()
            }
        }
    }

    var shortcutConflict: String? {
        ShortcutValidation.conflict(dictation: settings.dictationShortcut, prompt: settings.promptShortcut)
    }
}

extension ProfileStore {
    /// Used only if bundled profiles cannot be read, so Prompt Mode still works in a minimal form.
    static var fallback: ProfileStore {
        let generic = PromptProfile(
            id: "generic", name: "Generic AI", version: 1, philosophy: "", style: .init(heading: "colon", numberedWorkflow: false),
            sectionOrder: IntentSpec.sections,
            labels: ["en": Dictionary(uniqueKeysWithValues: IntentSpec.sections.map { ($0, $0.capitalized) })],
            signals: [], forbidden: [], extractorHints: ""
        )
        return ProfileStore(profiles: ["generic": generic], presets: [
            .quick: PresetConfig(sections: ["requirements"], signals: false, compact: true),
            .structured: PresetConfig(sections: IntentSpec.sections, signals: false, compact: false),
            .deep: PresetConfig(sections: IntentSpec.sections, signals: false, compact: false),
        ])
    }
}
