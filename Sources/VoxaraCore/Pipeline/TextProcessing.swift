import Foundation

/// Everything a processor needs to know about one recording.
public struct ProcessingContext: Sendable {
    public var mode: HotkeyAction
    public var language: SpeechLanguage
    public var targetBundleID: String?
    public var targetAppName: String?
    public var promptProfile: String
    public var promptPreset: PromptPreset
    public var cleanup: CleanupLevel
    public var outputLanguage: PromptOutputLanguage

    public init(mode: HotkeyAction, language: SpeechLanguage, targetBundleID: String? = nil, targetAppName: String? = nil,
                promptProfile: String = "generic", promptPreset: PromptPreset = .structured, cleanup: CleanupLevel = .smart,
                outputLanguage: PromptOutputLanguage = .sameAsSpeech) {
        self.mode = mode
        self.language = language
        self.targetBundleID = targetBundleID
        self.targetAppName = targetAppName
        self.promptProfile = promptProfile
        self.promptPreset = promptPreset
        self.cleanup = cleanup
        self.outputLanguage = outputLanguage
    }
}

public struct ProcessingResult: Sendable {
    public var text: String
    /// Short human-readable note about degraded processing (e.g. "AI unavailable — used basic cleanup").
    public var notice: String?
    /// Which processor produced the text (for history/debugging).
    public var processor: String

    public init(text: String, notice: String? = nil, processor: String) {
        self.text = text
        self.notice = notice
        self.processor = processor
    }
}

public enum ProcessingStage: Sendable, Equatable {
    case refining
    case buildingPrompt
}

/// Turns a raw transcript into the final text for the active mode.
public protocol TextProcessor: Sendable {
    func process(_ raw: String, context: ProcessingContext, onStage: @escaping @Sendable (ProcessingStage) -> Void) async -> ProcessingResult
}

/// Returns the transcript unchanged.
public struct PassthroughProcessor: TextProcessor {
    public init() {}

    public func process(_ raw: String, context: ProcessingContext, onStage: @escaping @Sendable (ProcessingStage) -> Void) async -> ProcessingResult {
        ProcessingResult(text: raw, processor: "raw")
    }
}
