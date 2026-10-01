import Foundation

/// Information about where the text will go, for context-aware processing.
public struct ProcessingContext: Sendable {
    public var mode: HotkeyAction
    public var language: SpeechLanguage
    public var targetBundleID: String?
    public var targetAppName: String?

    public init(mode: HotkeyAction, language: SpeechLanguage, targetBundleID: String? = nil, targetAppName: String? = nil) {
        self.mode = mode
        self.language = language
        self.targetBundleID = targetBundleID
        self.targetAppName = targetAppName
    }
}

public struct ProcessingResult: Sendable {
    public var text: String
    /// Short human-readable notes about degraded processing (e.g. "AI unavailable — used basic cleanup").
    public var notice: String?
    /// Which processor produced the text (for history/debugging).
    public var processor: String

    public init(text: String, notice: String? = nil, processor: String) {
        self.text = text
        self.notice = notice
        self.processor = processor
    }
}

/// Turns a raw transcript into the final text for the active mode
/// (dictation refinement or prompt compilation).
public protocol TextProcessor: Sendable {
    func process(_ raw: String, context: ProcessingContext, onStage: @escaping @Sendable (ProcessingStage) -> Void) async -> ProcessingResult
}

public enum ProcessingStage: Sendable, Equatable {
    case refining
    case buildingPrompt
}

/// Returns the transcript unchanged. Used in the walking skeleton and as a last-resort fallback.
public struct PassthroughProcessor: TextProcessor {
    public init() {}

    public func process(_ raw: String, context: ProcessingContext, onStage: @escaping @Sendable (ProcessingStage) -> Void) async -> ProcessingResult {
        ProcessingResult(text: raw, processor: "passthrough")
    }
}
