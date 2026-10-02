import Foundation

/// How much a dictation is cleaned up.
public enum CleanupLevel: String, Codable, CaseIterable, Sendable {
    /// Insert the transcript exactly as recognised.
    case off
    /// Rules only: fillers, stutters, spoken commands, spacing. No language model.
    case light
    /// Rules, plus the local model when the speech needs understanding (self-corrections, long dictations).
    case smart
    /// Rules plus the local model on every dictation.
    case thorough

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .light: "Light"
        case .smart: "Smart"
        case .thorough: "Thorough"
        }
    }

    public var explanation: String {
        switch self {
        case .off: "Insert exactly what was recognised."
        case .light: "Remove fillers and stutters, apply spoken punctuation. Instant, no AI."
        case .smart: "Light cleanup, plus the local model when you correct yourself or speak at length."
        case .thorough: "Light cleanup plus the local model on every dictation."
        }
    }
}

public enum PromptPreset: String, Codable, CaseIterable, Sendable {
    case quick
    case structured
    case deep

    public var displayName: String {
        switch self {
        case .quick: "Quick"
        case .structured: "Structured"
        case .deep: "Deep"
        }
    }

    public var explanation: String {
        switch self {
        case .quick: "Light restructuring into a clear, compact instruction."
        case .structured: "Organised instruction with the sections your request needs."
        case .deep: "For substantial agentic work: phases, investigation, validation and definition of done."
        }
    }
}

public enum PromptOutputLanguage: String, Codable, CaseIterable, Sendable {
    case sameAsSpeech
    case english

    public var displayName: String {
        switch self {
        case .sameAsSpeech: "Same as speech"
        case .english: "Always English"
        }
    }
}

/// All user preferences. Decoding tolerates missing keys so adding settings never resets old ones.
public struct AppSettings: Codable, Equatable, Sendable {
    public var dictationShortcut: Shortcut = .defaultDictation
    public var promptShortcut: Shortcut = .defaultPrompt
    public var language: SpeechLanguage = .auto

    public var cleanup: CleanupLevel = .smart
    public var vocabularyEnabled = true

    public var promptProfile = "generic"
    public var promptPreset: PromptPreset = .structured
    public var promptOutputLanguage: PromptOutputLanguage = .sameAsSpeech
    /// Let the focused app suggest the prompt profile and cleanup level.
    public var contextAware = true

    public var intelligenceModel = "qwen3:4b-instruct-2507-q4_K_M"
    public var ollamaURL = "http://127.0.0.1:11434"

    public var showOverlay = true
    public var playSounds = false
    public var saveHistory = true

    public var insertionMethod: InsertionMethod = .paste
    /// Development safety: insert only into Voxara's own test bench, never into other apps.
    public var testMode = false
    public var onboardingCompleted = false

    public init() {}

    public func shortcut(for action: HotkeyAction) -> Shortcut {
        action == .dictation ? dictationShortcut : promptShortcut
    }

    public var hotkeyBindings: [HotkeyAction: Shortcut] {
        [.dictation: dictationShortcut, .prompt: promptShortcut]
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        dictationShortcut = v(.dictationShortcut, d.dictationShortcut)
        promptShortcut = v(.promptShortcut, d.promptShortcut)
        language = v(.language, d.language)
        cleanup = v(.cleanup, d.cleanup)
        vocabularyEnabled = v(.vocabularyEnabled, d.vocabularyEnabled)
        promptProfile = v(.promptProfile, d.promptProfile)
        promptPreset = v(.promptPreset, d.promptPreset)
        promptOutputLanguage = v(.promptOutputLanguage, d.promptOutputLanguage)
        contextAware = v(.contextAware, d.contextAware)
        intelligenceModel = v(.intelligenceModel, d.intelligenceModel)
        ollamaURL = v(.ollamaURL, d.ollamaURL)
        showOverlay = v(.showOverlay, d.showOverlay)
        playSounds = v(.playSounds, d.playSounds)
        saveHistory = v(.saveHistory, d.saveHistory)
        insertionMethod = v(.insertionMethod, d.insertionMethod)
        testMode = v(.testMode, d.testMode)
        onboardingCompleted = v(.onboardingCompleted, d.onboardingCompleted)
    }
}

/// Loads and saves `AppSettings` in UserDefaults under one key.
public enum SettingsPersistence {
    public static let key = "voxara.settings.v1"

    public static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    public static func save(_ settings: AppSettings, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key) }
    }
}

/// Shortcut conflicts that would make one of the hotkeys unusable.
public enum ShortcutValidation {
    public static func conflict(dictation: Shortcut, prompt: Shortcut) -> String? {
        if dictation == prompt { return "Dictation and Prompt use the same shortcut." }
        return nil
    }

    /// Warnings for choices that interfere with normal macOS behaviour.
    public static func warning(for shortcut: Shortcut) -> String? {
        switch shortcut {
        case .modifier(.function):
            "fn is often used for input-source switching or system dictation. Check System Settings → Keyboard."
        case .modifier(.leftCommand), .modifier(.leftOption), .modifier(.leftControl), .modifier(.leftShift):
            "Left-side modifiers are used constantly for shortcuts and typing. A right-side key is more reliable."
        case .combo(_, let modifiers) where modifiers.isEmpty:
            "A shortcut without modifiers will block that key from typing."
        default:
            nil
        }
    }
}
