import AppKit
import SwiftUI
import VoxaraCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let log = VoxaraLog.logger("app")
    private var model: AppModel!
    private var menu: StatusMenuController!
    private var debugListener: DebugCommandListener?
    private let navigation = CommandCenterNavigation()
    private var commandCenter: NSWindow?
    private var onboarding: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        model = AppModel()
        model.start()
        menu = StatusMenuController(model: model, actions: .init(
            openCommandCenter: { [weak self] page in self?.showCommandCenter(page) },
            openOnboarding: { [weak self] in self?.showOnboarding() }
        ))
        if UserDefaults.standard.bool(forKey: "EnableDebugCommands") {
            debugListener = DebugCommandListener(model: model)
        }
        if !model.settings.onboardingCompleted { showOnboarding() }
        log.info("Voxara launched")
    }

    /// Reopening the app (Dock icon / Spotlight) opens the Command Center.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showCommandCenter(nil)
        return true
    }

    // MARK: Windows

    func showCommandCenter(_ page: CommandCenterPage?) {
        if let page { navigation.page = page }
        if commandCenter == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Voxara"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("VoxaraCommandCenter")
            window.delegate = self
            window.contentView = NSHostingView(rootView: CommandCenterView(model: model, navigation: navigation, openOnboarding: { [weak self] in
                self?.showOnboarding()
            }))
            window.center()
            commandCenter = window
        }
        present(commandCenter)
    }

    func showOnboarding() {
        if onboarding == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: OnboardingView(model: model, finish: { [weak self] in
                guard let self else { return }
                model.settings.onboardingCompleted = true
                onboarding?.close()
                showCommandCenter(.overview)
            }))
            window.center()
            onboarding = window
        }
        present(onboarding)
    }

    private func present(_ window: NSWindow?) {
        // A regular activation policy gives the window a Dock icon and menu bar while it is open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === onboarding {
            onboarding = nil
            // Closing the guide early still counts as seen, so it does not nag on every launch.
            model.settings.onboardingCompleted = true
        }
        if closing === commandCenter { commandCenter = nil }
        // Back to a menu-bar utility once no Voxara window is left.
        DispatchQueue.main.async {
            let anyVisible = NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) && $0.level == .normal }
            if !anyVisible { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
