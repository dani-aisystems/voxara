import Foundation

/// A test case for dictation refinement, shared by unit tests and `vt-bench refine`.
public struct DictationFixture: Codable, Sendable {
    public var id: String
    public var input: String
    /// Facts that must be present in the output (case-insensitive substring).
    public var mustContain: [String]
    /// Content that must be gone or never appear.
    public var mustNotContain: [String]

    public static func load(from url: URL) throws -> [DictationFixture] {
        try JSONDecoder().decode([DictationFixture].self, from: Data(contentsOf: url))
    }

    public struct Evaluation: Sendable {
        public var missing: [String]
        public var forbidden: [String]
        public var passed: Bool { missing.isEmpty && forbidden.isEmpty }
    }

    public func evaluate(_ output: String) -> Evaluation {
        let lower = output.lowercased()
        return Evaluation(
            missing: mustContain.filter { !lower.contains($0.lowercased()) },
            forbidden: mustNotContain.filter { lower.contains($0.lowercased()) }
        )
    }
}
