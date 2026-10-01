import FluidAudio
import Foundation

/// Parakeet TDT (v3 multilingual family) via FluidAudio / CoreML.
///
/// The `language` hint is deliberately *not* forwarded for Bulgarian: FluidAudio's script
/// filter rejects every Latin token for Cyrillic languages, which would delete English
/// technical terms embedded in Bulgarian speech ("dashboard", "API request").
public actor ParakeetTranscriber: SpeechTranscriber {
    public enum Variant: String, Codable, CaseIterable, Sendable {
        case v3
        case ultra

        var modelVersion: AsrModelVersion {
            switch self {
            case .v3: .v3
            case .ultra: .ultra
            }
        }

        public var displayName: String {
            switch self {
            case .v3: "Parakeet TDT v3"
            case .ultra: "Parakeet Ultra"
            }
        }
    }

    public nonisolated let variant: Variant
    public nonisolated var displayName: String { variant.displayName }

    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?

    public init(variant: Variant = .v3) {
        self.variant = variant
    }

    public var isReady: Bool { manager != nil }

    /// Whether the model files are already on disk (no network needed to load).
    public nonisolated static func isDownloaded(_ variant: Variant) -> Bool {
        let dir = AsrModels.defaultCacheDirectory(for: variant.modelVersion)
        return AsrModels.modelsExist(at: dir, version: variant.modelVersion)
    }

    public func prepare(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        _ = try await loadedManager(progress: progress)
    }

    private func loadedManager(progress: (@Sendable (Double) -> Void)? = nil) async throws -> AsrManager {
        if let manager { return manager }
        if let loading { return try await loading.value }
        let version = variant.modelVersion
        let task = Task<AsrManager, Error> {
            let models = try await AsrModels.downloadAndLoad(
                version: version,
                progressHandler: { p in progress?(p.fractionCompleted) }
            )
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        loading = task
        do {
            let manager = try await task.value
            self.manager = manager
            loading = nil
            return manager
        } catch {
            loading = nil
            throw error
        }
    }

    public func transcribe(samples: [Float], language: SpeechLanguage) async throws -> TranscriptionResult {
        // Parakeet needs at least ~1s of audio; pad short clips with silence.
        guard samples.count >= Int(AudioFormat.sampleRate * 0.2) else { throw SpeechError.audioTooShort }
        var input = samples
        let minimum = Int(AudioFormat.sampleRate * 1.0)
        if input.count < minimum { input += [Float](repeating: 0, count: minimum - input.count) }

        let manager = try await loadedManager()
        let start = Date()
        var state = TdtDecoderState.make()
        let hint: Language? = language == .english ? .english : nil
        do {
            let result = try await manager.transcribe(input, decoderState: &state, language: hint)
            return TranscriptionResult(
                text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                confidence: result.confidence,
                audioDuration: Double(samples.count) / AudioFormat.sampleRate,
                processingTime: Date().timeIntervalSince(start)
            )
        } catch {
            throw SpeechError.engineFailed(error.localizedDescription)
        }
    }
}
