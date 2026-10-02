import AppKit
import Observation
import VoxaraCore

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    struct Actions {
        var openCommandCenter: (CommandCenterPage?) -> Void
        var openOnboarding: () -> Void
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private let actions: Actions
    private let menu = NSMenu()

    init(model: AppModel, actions: Actions) {
        self.model = model
        self.actions = actions
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        configureButton()
        observe()
    }

    // MARK: Icon

    private func configureButton() {
        guard let button = item.button else { return }
        if let url = Bundle.main.url(forResource: "menubar-template@2x", withExtension: "png"), let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voxara")
        }
        button.toolTip = "Voxara"
    }

    /// Re-renders the icon whenever pipeline state or permissions change.
    private func observe() {
        withObservationTracking {
            _ = model.pipelineState
            _ = model.accessibilityGranted
            _ = model.microphoneAuthorized
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshIcon()
                self?.observe()
            }
        }
        refreshIcon()
    }

    private func refreshIcon() {
        guard let button = item.button else { return }
        switch model.pipelineState {
        case .listening: button.contentTintColor = NSColor(VX.Palette.accent)
        case .failed: button.contentTintColor = NSColor(VX.Palette.warning)
        default: button.contentTintColor = nil
        }
        button.appearsDisabled = !model.accessibilityGranted || !model.microphoneAuthorized
    }

    // MARK: Menu (rebuilt each time it opens, so it is always current)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = model.settings

        add(statusTitle(), enabled: false)
        if let warning = permissionWarning() { add(warning, enabled: true, action: #selector(openPermissionHelp)) }
        menu.addItem(.separator())

        add("Dictation   ·   \(settings.dictationShortcut.displayName)", enabled: false)
        add("Prompt        ·   \(settings.promptShortcut.displayName)", enabled: false)
        menu.addItem(.separator())

        menu.addItem(submenu("Prompt Profile", items: model.profiles.ordered.map { profile in
            check(profile.name, on: settings.promptProfile == profile.id) { [model] in model.settings.promptProfile = profile.id }
        }))
        menu.addItem(submenu("Preset", items: PromptPreset.allCases.map { preset in
            check(preset.displayName, on: settings.promptPreset == preset) { [model] in model.settings.promptPreset = preset }
        }))
        menu.addItem(submenu("Language", items: SpeechLanguage.allCases.map { language in
            check(language.displayName, on: settings.language == language) { [model] in model.settings.language = language }
        }))
        menu.addItem(submenu("Cleanup", items: CleanupLevel.allCases.map { level in
            check(level.displayName, on: settings.cleanup == level) { [model] in model.settings.cleanup = level }
        }))
        menu.addItem(.separator())

        let copy = add("Copy Last Result", enabled: model.pipeline.lastResult != nil, action: #selector(copyLast))
        copy.keyEquivalent = ""
        menu.addItem(.separator())

        add("Open Command Center", enabled: true, action: #selector(openOverview)).keyEquivalent = ","
        add("History", enabled: true, action: #selector(openHistory))
        add("Settings", enabled: true, action: #selector(openSettings))
        add("Welcome Guide…", enabled: true, action: #selector(openWelcome))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Voxara", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func statusTitle() -> String {
        if settings.testMode { return "◐ Test mode" }
        switch model.pipelineState {
        case .listening: return "● Listening…"
        case .transcribing: return "● Transcribing…"
        case .processing(_, .refining): return "● Refining…"
        case .processing(_, .buildingPrompt): return "● Building prompt…"
        case .failed(let message, _): return "⚠︎ \(message)"
        default:
            switch model.speechModelStatus {
            case .loading: return "○ Loading speech model…"
            case .failed: return "⚠︎ Speech model unavailable"
            case .ready: return "● Ready"
            }
        }
    }

    private var settings: AppSettings { model.settings }

    private func permissionWarning() -> String? {
        if !model.accessibilityGranted { return "⚠︎ Allow Accessibility to enable hotkeys…" }
        if !model.microphoneAuthorized { return "⚠︎ Allow Microphone access…" }
        return nil
    }

    // MARK: Helpers

    private var handlers: [ObjectIdentifier: () -> Void] = [:]

    @discardableResult
    private func add(_ title: String, enabled: Bool, action: Selector? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
        return item
    }

    private func check(_ title: String, on: Bool, perform: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runHandler(_:)), keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        handlers[ObjectIdentifier(item)] = perform
        return item
    }

    private func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        items.forEach(sub.addItem)
        parent.submenu = sub
        return parent
    }

    @objc private func runHandler(_ sender: NSMenuItem) { handlers[ObjectIdentifier(sender)]?() }
    @objc private func copyLast() { model.copyLastResult() }
    @objc private func openOverview() { actions.openCommandCenter(.overview) }
    @objc private func openHistory() { actions.openCommandCenter(.history) }
    @objc private func openSettings() { actions.openCommandCenter(.settings) }
    @objc private func openWelcome() { actions.openOnboarding() }
    @objc private func openPermissionHelp() {
        if !model.accessibilityGranted { Permissions.openAccessibilitySettings() } else { Permissions.openMicrophoneSettings() }
    }
}
