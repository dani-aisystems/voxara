import Foundation

/// Language preference for transcription. `auto` lets the engine detect the language,
/// which is required for Bulgarian speech that embeds English technical terms.
public enum SpeechLanguage: String, Codable, CaseIterable, Sendable {
    case auto
    case english
    case bulgarian

    public var displayName: String {
        switch self {
        case .auto: "Auto"
        case .english: "English"
        case .bulgarian: "Bulgarian"
        }
    }
}

public struct TranscriptionResult: Sendable, Equatable {
    public var text: String
    public var confidence: Float?
    /// Audio duration in seconds.
    public var audioDuration: TimeInterval
    /// Wall-clock time spent in the engine.
    public var processingTime: TimeInterval

    public init(text: String, confidence: Float? = nil, audioDuration: TimeInterval, processingTime: TimeInterval) {
        self.text = text
        self.confidence = confidence
        self.audioDuration = audioDuration
        self.processingTime = processingTime
    }
}

public enum SpeechError: LocalizedError, Equatable {
    case modelNotLoaded
    case audioTooShort
    case engineFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "The speech model is not loaded yet."
        case .audioTooShort: "The recording was too short to transcribe."
        case .engineFailed(let message): "Transcription failed: \(message)"
        }
    }
}

/// Speech-to-text engine abstraction. Input is always 16 kHz mono Float32 PCM.
public protocol SpeechTranscriber: Sendable {
    var displayName: String { get }
    var isReady: Bool { get async }
    func prepare(progress: (@Sendable (Double) -> Void)?) async throws
    func transcribe(samples: [Float], language: SpeechLanguage) async throws -> TranscriptionResult
}

public enum AudioFormat {
    public static let sampleRate: Double = 16_000
}
