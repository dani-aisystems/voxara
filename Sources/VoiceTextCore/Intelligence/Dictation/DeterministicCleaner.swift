import Foundation

/// Fast, rule-based cleanup that runs on every dictation with no model involved.
///
/// It only removes things that carry no meaning (hesitations, stutters) and normalises
/// spacing and capitalisation. It never rewrites, reorders or summarises.
public struct DeterministicCleaner: Sendable {
    public var applySpokenCommands: Bool

    public init(applySpokenCommands: Bool = true) {
        self.applySpokenCommands = applySpokenCommands
    }

    /// Pure hesitation sounds. Safe to drop anywhere they appear as whole words.
    private static let hesitations: [String] = [
        "um", "umm", "uh", "uhh", "uhm", "er", "erm", "hmm", "hm", "mhm", "mm",
        "ъъ", "ъ", "ъм", "ъъм", "ъъъ", "ем", "еъ", "хм", "ммм",
    ]

    /// Discourse fillers that are only removed at the very start of an utterance or sentence,
    /// where they are almost never part of the meaning ("like" and "well" can be, mid-sentence).
    private static let leadingFillers: [String] = [
        "so basically", "okay so basically", "okay so", "ok so", "so yeah", "yeah so", "you know",
        "i mean", "like", "well", "so", "okay", "ok", "basically", "actually",
        "ами", "значи", "така", "добре де", "нали",
    ]

    public func clean(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        s = removeHesitations(s)
        s = collapseStutters(s)
        if applySpokenCommands { s = SpokenCommandParser.apply(to: s) }
        s = removeLeadingFillers(s)
        s = normalizeWhitespace(s)
        s = capitalizeSentences(s)
        return s
    }

    // MARK: - Steps

    func removeHesitations(_ text: String) -> String {
        let alternation = Self.hesitations.sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        // Whole-word match plus any trailing comma/ellipsis the STT attached to it.
        let pattern = "(?<![\\p{L}\\p{N}'’-])(?:\(alternation))(?![\\p{L}\\p{N}'’-])(?:\\s*[,.…]+)?\\s*"
        return text.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
    }

    /// "I I think" → "I think"; "the the" → "the". Only collapses immediate repeats of short function-like
    /// words and word fragments, so intentional repetition ("very, very good", "ha ha") is left alone.
    func collapseStutters(_ text: String) -> String {
        // Hyphenated stutters: "wh-what" / "th-the" → "what" / "the".
        var s = text.replacingOccurrences(
            of: "(?<![\\p{L}\\p{N}])(\\p{L}{1,3})-(\\1\\p{L}*)", with: "$2",
            options: [.regularExpression, .caseInsensitive]
        )
        // Immediate duplicate of a short word, with no punctuation between.
        s = s.replacingOccurrences(
            of: "(?<![\\p{L}\\p{N}'’])(\\p{L}{1,4})(?:\\s+\\1)+(?![\\p{L}\\p{N}'’])", with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
        return s
    }

    func removeLeadingFillers(_ text: String) -> String {
        var s = text
        // Repeat so "Okay so basically, um" style stacks are fully removed.
        for _ in 0..<3 {
            var changed = false
            for filler in Self.leadingFillers.sorted(by: { $0.count > $1.count }) {
                let pattern = "^(\\s*)\(NSRegularExpression.escapedPattern(for: filler).replacingOccurrences(of: "\\ ", with: "\\s+"))(?![\\p{L}\\p{N}])\\s*[,]?\\s+"
                if let range = s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    s.replaceSubrange(range, with: "")
                    changed = true
                    break
                }
            }
            if !changed { break }
        }
        return s
    }

    func normalizeWhitespace(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: " ([,.;:?!])", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "^[,.;:\\s]+", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: ",\\s*,", with: ",", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func capitalizeSentences(_ text: String) -> String {
        let chars = Array(text)
        var result = ""
        var capitalizeNext = true
        for (i, ch) in chars.enumerated() {
            if capitalizeNext, ch.isLetter {
                result.append(contentsOf: String(ch).uppercased())
                capitalizeNext = false
            } else {
                result.append(ch)
                if ch.isLetter || ch.isNumber { capitalizeNext = false }
            }
            // A sentence ends at ./!/? only when followed by whitespace or the end ("Next.js" stays intact).
            if ch == "\n" {
                capitalizeNext = true
            } else if ch == "." || ch == "!" || ch == "?" {
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                if next.isWhitespace { capitalizeNext = true }
            }
        }
        return result
    }
}
