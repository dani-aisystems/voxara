import Foundation
import Observation

/// Local dictation history stored as a JSON file. Text only; never audio.
@MainActor
@Observable
public final class HistoryStore {
    public private(set) var entries: [DictationRecord] = []
    public let fileURL: URL
    public var limit: Int

    public init(fileURL: URL = VoxaraPaths.supportDirectory.appendingPathComponent("history.json"), limit: Int = 1000) {
        self.fileURL = fileURL
        self.limit = limit
        entries = JSONFile.read([DictationRecord].self, from: fileURL) ?? []
    }

    public func add(_ record: DictationRecord) {
        entries.insert(record, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        persist()
    }

    public func delete(_ id: DictationRecord.ID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    public func clear() {
        entries.removeAll()
        persist()
    }

    public func search(_ query: String, mode: HotkeyAction? = nil) -> [DictationRecord] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.filter { entry in
            (mode == nil || entry.mode == mode)
                && (q.isEmpty || entry.finalText.lowercased().contains(q) || entry.rawTranscript.lowercased().contains(q)
                    || (entry.targetApp?.lowercased().contains(q) ?? false))
        }
    }

    private func persist() {
        try? JSONFile.write(entries, to: fileURL)
    }
}

/// Aggregates computed from real history entries only; nothing is estimated.
public struct UsageStats: Sendable, Equatable {
    public var count: Int
    public var dictations: Int
    public var prompts: Int
    public var secondsSpoken: TimeInterval
    public var medianSTT: TimeInterval?
    public var medianCleanup: TimeInterval?
    public var medianPrompt: TimeInterval?
    public var medianTotal: TimeInterval?

    public static func compute(_ records: [DictationRecord]) -> UsageStats {
        func median(_ values: [TimeInterval]) -> TimeInterval? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            let mid = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }
        let dictation = records.filter { $0.mode == .dictation }
        let prompt = records.filter { $0.mode == .prompt }
        return UsageStats(
            count: records.count,
            dictations: dictation.count,
            prompts: prompt.count,
            secondsSpoken: records.compactMap(\.timings.audioDuration).reduce(0, +),
            medianSTT: median(records.compactMap(\.timings.stt)),
            // Only count cleanup runs that actually used the model; rule-only cleanup is ~0 ms and would hide model latency.
            medianCleanup: median(dictation.filter { $0.processor != "rules" && $0.processor != "raw" }.compactMap(\.timings.processing)),
            medianPrompt: median(prompt.compactMap(\.timings.processing)),
            medianTotal: median(records.compactMap(\.timings.perceived))
        )
    }

    public static func today(_ records: [DictationRecord], calendar: Calendar = .current, now: Date = Date()) -> UsageStats {
        compute(records.filter { calendar.isDate($0.date, inSameDayAs: now) })
    }
}
