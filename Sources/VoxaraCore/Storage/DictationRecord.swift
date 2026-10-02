import Foundation

/// Language actually detected in a transcript (by script), for history display.
public enum DetectedLanguage: String, Codable, Sendable {
    case english, bulgarian, mixed, unknown

    public var displayName: String {
        switch self {
        case .english: "English"
        case .bulgarian: "Bulgarian"
        case .mixed: "Mixed"
        case .unknown: "—"
        }
    }

    public static func of(_ text: String) -> DetectedLanguage {
        switch TextScript.dominant(in: text) {
        case .english: .english
        case .bulgarian: .bulgarian
        case .mixed: .mixed
        case .none: .unknown
        }
    }
}

/// One finished dictation or prompt. Text only: audio is never stored.
public struct DictationRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var date: Date
    public var mode: HotkeyAction
    public var detectedLanguage: DetectedLanguage
    public var rawTranscript: String
    public var finalText: String
    public var targetApp: String?
    public var targetBundleID: String?
    /// Which processor produced the text ("rules", "ollama", "prompt-compiler", "fallback", …).
    public var processor: String
    public var promptProfile: String?
    public var promptPreset: PromptPreset?
    public var cleanup: CleanupLevel?
    public var inserted: Bool
    public var notice: String?
    public var timings: PipelineTimings

    public init(id: UUID = UUID(), date: Date, mode: HotkeyAction, rawTranscript: String, finalText: String,
                targetApp: String?, targetBundleID: String?, processor: String, promptProfile: String? = nil,
                promptPreset: PromptPreset? = nil, cleanup: CleanupLevel? = nil, inserted: Bool,
                notice: String? = nil, timings: PipelineTimings) {
        self.id = id
        self.date = date
        self.mode = mode
        self.detectedLanguage = DetectedLanguage.of(rawTranscript)
        self.rawTranscript = rawTranscript
        self.finalText = finalText
        self.targetApp = targetApp
        self.targetBundleID = targetBundleID
        self.processor = processor
        self.promptProfile = promptProfile
        self.promptPreset = promptPreset
        self.cleanup = cleanup
        self.inserted = inserted
        self.notice = notice
        self.timings = timings
    }
}
