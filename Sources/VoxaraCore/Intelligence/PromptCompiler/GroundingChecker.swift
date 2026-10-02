import Foundation

/// Removes extracted items that cannot be traced back to what the speaker actually said.
public struct GroundingChecker: Sendable {
    public struct Report: Sendable, Equatable {
        public var spec: IntentSpec
        public var dropped: [String]
    }

    /// Words too common to prove an item is grounded.
    static let stopwords: Set<String> = [
        "the", "and", "for", "that", "this", "with", "from", "into", "are", "was", "were", "has", "have", "had", "not",
        "but", "all", "any", "can", "will", "should", "must", "make", "sure", "does", "doing", "before", "after", "then",
        "first", "only", "also", "about", "when", "than", "their", "there", "them", "they", "your", "its", "use", "used",
        "using", "keep", "work", "what", "which", "being", "been", "each", "other", "more", "most", "such", "without",
        "и", "на", "да", "за", "от", "със", "със", "при", "като", "или", "но", "не", "се", "ще", "си", "по", "до", "че",
        "това", "тази", "този", "тези", "само", "после", "преди", "след", "първо", "който", "която", "които",
    ]

    /// Minimum share of an item's content words that must appear (by stem) in the transcript.
    public var minimumOverlap: Double

    public init(minimumOverlap: Double = 0.5) {
        self.minimumOverlap = minimumOverlap
    }

    public func ground(_ spec: IntentSpec, transcript: String, checkWords: Bool = true) -> Report {
        guard checkWords else { return Report(spec: spec, dropped: []) }
        let source = TextScript.words(transcript)
        var result = spec
        var dropped: [String] = []

        func keep(_ item: String) -> Bool {
            let content = TextScript.words(item).filter { $0.count >= 3 && !Self.stopwords.contains($0) }
            guard !content.isEmpty else { return true }
            let hits = content.filter { word in source.contains { Self.sameWord($0, word) } }.count
            return Double(hits) / Double(content.count) >= minimumOverlap
        }

        for section in IntentSpec.sections {
            let items = spec[section]
            let kept = items.filter { item in
                let ok = keep(item)
                if !ok { dropped.append(item) }
                return ok
            }
            result[section] = kept
        }
        if !keep(spec.objective) {
            dropped.append(spec.objective)
            result.objective = ""
        }
        return Report(spec: result, dropped: dropped)
    }

    /// Two words match when one is (almost) a prefix of the other: handles English inflection and
    /// Bulgarian articles/plurals ("зарежда" ~ "зареждането") without a stemmer.
    static func sameWord(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let x = Array(a), y = Array(b)
        var common = 0
        while common < min(x.count, y.count), x[common] == y[common] { common += 1 }
        return common >= max(4, min(x.count, y.count) - 2)
    }

    /// Crude stem good enough for English inflection and Bulgarian endings (articles, plurals).
    static func stem(_ word: String) -> String {
        let w = word.lowercased()
        return String(w.prefix(max(4, w.count - 3)))
    }
}
