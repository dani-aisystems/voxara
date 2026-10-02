import Foundation
import Observation

/// Per-application behaviour, keyed by bundle identifier. `nil` fields mean "use the suggestion / global default".
public struct AppPreference: Codable, Sendable, Equatable, Identifiable {
    public var bundleID: String
    public var displayName: String
    public var promptProfile: String?
    public var cleanup: CleanupLevel?
    /// Opt-in: make the *dictation* key produce a compiled prompt in this app.
    public var dictationKeyProducesPrompt: Bool
    public var lastSeen: Date

    public var id: String { bundleID }

    public init(bundleID: String, displayName: String, promptProfile: String? = nil, cleanup: CleanupLevel? = nil,
                dictationKeyProducesPrompt: Bool = false, lastSeen: Date = Date()) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.promptProfile = promptProfile
        self.cleanup = cleanup
        self.dictationKeyProducesPrompt = dictationKeyProducesPrompt
        self.lastSeen = lastSeen
    }
}

/// What the focused app suggests. Conservative: suggestions only change the prompt profile and the
/// cleanup level, never the meaning of the hotkeys.
public struct AppSuggestion: Sendable, Equatable {
    public var promptProfile: String?
    public var cleanup: CleanupLevel?
    public var category: String
}

public enum AppCatalog {
    /// Built-in suggestions for well-known apps.
    public static func suggestion(bundleID: String?, windowTitle: String? = nil) -> AppSuggestion? {
        guard let bundleID else { return nil }
        if let entry = known[bundleID] { return entry }
        // Browsers: infer only from the page title, and only for unambiguous AI chat sites.
        if browsers.contains(bundleID), let title = windowTitle?.lowercased() {
            if title.contains("chatgpt") { return AppSuggestion(promptProfile: "chatgpt", cleanup: nil, category: "AI chat (web)") }
            if title.contains("claude") { return AppSuggestion(promptProfile: "claude", cleanup: nil, category: "AI chat (web)") }
        }
        return nil
    }

    static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "org.mozilla.firefox",
        "company.thebrowser.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    static let known: [String: AppSuggestion] = {
        var map: [String: AppSuggestion] = [:]
        let coding = AppSuggestion(promptProfile: "claude-code", cleanup: nil, category: "Terminal / code editor")
        for id in ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
                   "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.google.antigravity", "com.google.antigravity-ide",
                   "com.jetbrains.pycharm", "com.jetbrains.pycharm.ce", "dev.zed.Zed", "com.exafunction.windsurf"] {
            map[id] = coding
        }
        for id in ["com.openai.chat", "com.openai.codex"] {
            map[id] = AppSuggestion(promptProfile: "chatgpt", cleanup: nil, category: "AI chat")
        }
        map["com.google.GeminiMacOS"] = AppSuggestion(promptProfile: "generic", cleanup: nil, category: "AI chat")
        map["com.anthropic.claudefordesktop"] = AppSuggestion(promptProfile: "claude", cleanup: nil, category: "AI chat")
        let light = AppSuggestion(promptProfile: nil, cleanup: .light, category: "Messaging")
        for id in ["com.apple.MobileSMS", "com.viber.osx", "com.hnc.Discord", "com.tinyspeck.slackmacgap", "net.whatsapp.WhatsApp"] {
            map[id] = light
        }
        map["com.apple.mail"] = AppSuggestion(promptProfile: nil, cleanup: nil, category: "Email")
        map["notion.id"] = AppSuggestion(promptProfile: nil, cleanup: nil, category: "Notes / docs")
        map["com.apple.Notes"] = AppSuggestion(promptProfile: nil, cleanup: nil, category: "Notes / docs")
        return map
    }()
}

/// The effective behaviour for one recording, after combining global settings, app suggestions
/// and explicit per-app overrides (explicit always wins).
public struct ResolvedContext: Sendable, Equatable {
    public var mode: HotkeyAction
    public var promptProfile: String
    public var promptPreset: PromptPreset
    public var cleanup: CleanupLevel
    /// Human-readable reason, shown in history and the Applications page.
    public var source: String

    public init(mode: HotkeyAction, promptProfile: String, promptPreset: PromptPreset, cleanup: CleanupLevel, source: String) {
        self.mode = mode
        self.promptProfile = promptProfile
        self.promptPreset = promptPreset
        self.cleanup = cleanup
        self.source = source
    }

    public static func resolve(action: HotkeyAction, bundleID: String?, windowTitle: String?,
                               settings: AppSettings, preference: AppPreference?) -> ResolvedContext {
        var result = ResolvedContext(mode: action, promptProfile: settings.promptProfile, promptPreset: settings.promptPreset,
                                     cleanup: settings.cleanup, source: "Default")
        if settings.contextAware, let suggestion = AppCatalog.suggestion(bundleID: bundleID, windowTitle: windowTitle) {
            if let profile = suggestion.promptProfile { result.promptProfile = profile }
            // Suggestions may only make cleanup lighter, never heavier, so they cannot change meaning.
            if let cleanup = suggestion.cleanup, cleanup.rank < result.cleanup.rank { result.cleanup = cleanup }
            result.source = "Suggested for \(suggestion.category)"
        }
        if let preference {
            if let profile = preference.promptProfile { result.promptProfile = profile; result.source = "App setting" }
            if let cleanup = preference.cleanup { result.cleanup = cleanup; result.source = "App setting" }
            if action == .dictation, preference.dictationKeyProducesPrompt {
                result.mode = .prompt
                result.source = "App setting"
            }
        }
        return result
    }
}

extension CleanupLevel {
    var rank: Int {
        switch self {
        case .off: 0
        case .light: 1
        case .smart: 2
        case .thorough: 3
        }
    }
}

/// Stores per-app preferences and remembers which apps Voxara has been used in.
@MainActor
@Observable
public final class AppPreferencesStore {
    public private(set) var apps: [String: AppPreference] = [:]
    private let fileURL: URL

    public init(fileURL: URL = VoxaraPaths.supportDirectory.appendingPathComponent("applications.json")) {
        self.fileURL = fileURL
        let list = JSONFile.read([AppPreference].self, from: fileURL) ?? []
        apps = Dictionary(list.map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public var sorted: [AppPreference] {
        apps.values.sorted { $0.lastSeen > $1.lastSeen }
    }

    public func preference(for bundleID: String?) -> AppPreference? {
        bundleID.flatMap { apps[$0] }
    }

    /// Records that Voxara was used in an app (so it appears on the Applications page).
    public func noteUsage(bundleID: String?, name: String?) {
        guard let bundleID, bundleID != Bundle.main.bundleIdentifier else { return }
        var pref = apps[bundleID] ?? AppPreference(bundleID: bundleID, displayName: name ?? bundleID)
        pref.lastSeen = Date()
        if let name { pref.displayName = name }
        apps[bundleID] = pref
        persist()
    }

    public func update(_ preference: AppPreference) {
        apps[preference.bundleID] = preference
        persist()
    }

    public func remove(_ bundleID: String) {
        apps[bundleID] = nil
        persist()
    }

    private func persist() {
        try? JSONFile.write(sorted, to: fileURL)
    }
}
