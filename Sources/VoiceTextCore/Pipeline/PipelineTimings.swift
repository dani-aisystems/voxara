import Foundation

/// Wall-clock checkpoints for one dictation, used for latency instrumentation.
public struct PipelineTimings: Codable, Sendable, Equatable {
    public var recordingStarted: Date?
    public var recordingEnded: Date?
    public var audioPrepared: Date?
    public var sttStarted: Date?
    public var sttCompleted: Date?
    public var processingStarted: Date?
    public var processingCompleted: Date?
    public var injected: Date?

    public init() {}

    public var audioDuration: TimeInterval? { interval(recordingStarted, recordingEnded) }
    public var stt: TimeInterval? { interval(sttStarted, sttCompleted) }
    public var processing: TimeInterval? { interval(processingStarted, processingCompleted) }
    /// Release of the hotkey to text appearing — the latency the user feels.
    public var perceived: TimeInterval? { interval(recordingEnded, injected) }

    public var summary: String {
        func ms(_ value: TimeInterval?) -> String { value.map { "\(Int($0 * 1000))ms" } ?? "–" }
        return "audio \(audioDuration.map { String(format: "%.1fs", $0) } ?? "–") · stt \(ms(stt)) · ai \(ms(processing)) · total \(ms(perceived))"
    }

    private func interval(_ start: Date?, _ end: Date?) -> TimeInterval? {
        guard let start, let end else { return nil }
        return end.timeIntervalSince(start)
    }
}
