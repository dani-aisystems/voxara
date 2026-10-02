import Foundation

/// A Prompt Mode test case. Quality is judged on meaning, never on exact wording.
public struct PromptFixture: Codable, Sendable {
    public var id: String
    public var category: String
    public var profile: String
    public var input: String
    /// Each group is a concept that must appear; any one of its alternatives (synonym or translation) satisfies it.
    public var mustPreserve: [[String]]
    /// Terms the speaker never said and the prompt must not introduce (whole-word, case-insensitive).
    public var mustNotInvent: [String]
    /// Section labels expected in the Structured output (e.g. "Validation"), checked only when non-empty.
    public var expectedSections: [String]

    public static func load(from url: URL) throws -> [PromptFixture] {
        try JSONDecoder().decode([PromptFixture].self, from: Data(contentsOf: url))
    }

    public struct Evaluation: Sendable {
        public var missingConcepts: [String]
        public var invented: [String]
        public var missingSections: [String]
        public var passed: Bool { missingConcepts.isEmpty && invented.isEmpty && missingSections.isEmpty }
        public var summary: String {
            var parts: [String] = []
            if !missingConcepts.isEmpty { parts.append("missing: \(missingConcepts.joined(separator: " | "))") }
            if !invented.isEmpty { parts.append("invented: \(invented.joined(separator: ", "))") }
            if !missingSections.isEmpty { parts.append("sections: \(missingSections.joined(separator: ", "))") }
            return parts.joined(separator: "; ")
        }
    }

    public func evaluate(_ prompt: String) -> Evaluation {
        let lower = prompt.lowercased()
        let missing = mustPreserve.filter { group in !group.contains { lower.contains($0.lowercased()) } }
            .map { $0.first ?? "?" }
        let spoken = input.lowercased()
        let invented = mustNotInvent.filter { term in
            let t = term.lowercased()
            guard !spoken.contains(t) else { return false }
            return Self.containsWord(t, in: lower)
        }
        let missingSections = expectedSections.filter { !lower.contains($0.lowercased()) }
        return Evaluation(missingConcepts: missing, invented: invented, missingSections: missingSections)
    }

    static func containsWord(_ word: String, in text: String) -> Bool {
        let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: word))(?![\\p{L}\\p{N}])"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
