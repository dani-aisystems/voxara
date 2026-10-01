import Foundation

/// Validates model output against the transcript it was derived from, so a small local model
/// cannot silently answer the speaker, translate, summarise, or invent content.
public enum OutputGuards {
    public enum Violation: Equatable, Sendable, CustomStringConvertible {
        case empty
        case tooLong(ratio: Double)
        case tooShort(ratio: Double)
        case languageChanged
        case inventedNumbers([String])
        case inventedWords(fraction: Double)
        case repliedToSpeaker
        case droppedTerms([String])

        public var description: String {
            switch self {
            case .empty: "empty output"
            case .tooLong(let r): "output \(String(format: "%.2f", r))× longer than input"
            case .tooShort(let r): "output only \(String(format: "%.2f", r))× of input"
            case .languageChanged: "language/script changed"
            case .inventedNumbers(let n): "new numbers: \(n.joined(separator: ", "))"
            case .inventedWords(let f): "\(Int(f * 100))% of words not in input"
            case .repliedToSpeaker: "reply to the speaker instead of cleanup"
            case .droppedTerms(let t): "dropped terms: \(t.joined(separator: ", "))"
            }
        }
    }

    public struct Limits: Sendable {
        public var minRatio = 0.35
        public var maxRatio = 1.25
        public var maxInventedWordFraction = 0.2

        public init() {}
    }

    private static let replyOpeners = [
        "sure", "certainly", "of course", "here is", "here's", "i'm sorry", "i am sorry", "as an ai",
        "i cannot", "i can't", "unfortunately", "great question", "okay,", "absolutely",
        "разбира се", "ето ", "съжалявам", "като изкуствен",
    ]

    public static func check(input: String, output: String, limits: Limits = Limits()) -> [Violation] {
        var violations: [Violation] = []
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [.empty] }

        let ratio = Double(trimmed.count) / Double(max(input.count, 1))
        if ratio > limits.maxRatio { violations.append(.tooLong(ratio: ratio)) }
        if ratio < limits.minRatio { violations.append(.tooShort(ratio: ratio)) }

        if TextScript.dominant(in: input) != TextScript.dominant(in: trimmed),
           TextScript.dominant(in: input) != .mixed, TextScript.dominant(in: trimmed) != .mixed {
            violations.append(.languageChanged)
        } else if scriptShareChanged(input: input, output: trimmed) {
            violations.append(.languageChanged)
        }

        let inputNumbers = Set(numbers(in: input))
        let invented = numbers(in: trimmed).filter { !inputNumbers.contains($0) }
        if !invented.isEmpty { violations.append(.inventedNumbers(invented)) }

        let inputWords = Set(TextScript.words(input))
        let outputWords = TextScript.words(trimmed)
        if !outputWords.isEmpty {
            let novel = outputWords.filter { !inputWords.contains($0) && !isInflectionOfInputWord($0, inputWords) }
            let fraction = Double(novel.count) / Double(outputWords.count)
            if fraction > limits.maxInventedWordFraction { violations.append(.inventedWords(fraction: fraction)) }
        }

        let lowerOut = trimmed.lowercased()
        let lowerIn = input.lowercased()
        if replyOpeners.contains(where: { lowerOut.hasPrefix($0) && !lowerIn.hasPrefix($0) }) {
            violations.append(.repliedToSpeaker)
        }
        return violations
    }

    /// Latin-script terms (acronyms, product names, code-ish words) that must survive when the
    /// transcript is Bulgarian: models tend to "helpfully" translate them. Returns the ones missing
    /// from `output`. English text is not checked because every word there is Latin.
    public static func missingLatinTerms(input: String, output: String) -> [String] {
        guard TextScript.dominant(in: input) != .english else { return [] }
        let lowerOutput = output.lowercased()
        return latinTerms(in: input).filter { !lowerOutput.contains($0.lowercased()) }
    }

    /// Latin words inside a text. Hyphenated mixed tokens such as "request-ите" yield their Latin stem.
    public static func latinTerms(in text: String) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []
        for token in text.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }) {
            let word = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "_."))
            guard word.count >= 2, word.unicodeScalars.contains(where: TextScript.isLatinLetter),
                  !word.unicodeScalars.contains(where: TextScript.isCyrillic) else { continue }
            if seen.insert(word.lowercased()).inserted { terms.append(word) }
        }
        return terms
    }

    static func numbers(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\d+(?:[.,]\\d+)*") else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .map { $0.replacingOccurrences(of: ",", with: "") }
    }

    /// Cyrillic share must stay close to the input's (catches partial translation).
    private static func scriptShareChanged(input: String, output: String) -> Bool {
        let a = TextScript.counts(in: input)
        let b = TextScript.counts(in: output)
        guard a.letters > 20, b.letters > 0 else { return false }
        let shareIn = Double(a.cyrillic) / Double(a.letters)
        let shareOut = Double(b.cyrillic) / Double(b.letters)
        return abs(shareIn - shareOut) > 0.35
    }

    /// Allows trivial morphological variants (plural, tense) of words that were in the input.
    private static func isInflectionOfInputWord(_ word: String, _ inputWords: Set<String>) -> Bool {
        guard word.count >= 5 else { return false }
        let stem = String(word.prefix(max(4, word.count - 3)))
        return inputWords.contains { $0.hasPrefix(stem) }
    }
}
