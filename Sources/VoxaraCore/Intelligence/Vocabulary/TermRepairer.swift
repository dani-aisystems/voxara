import AppKit
import Foundation

/// Decides whether a Cyrillic word is genuine Bulgarian. Genuine words are never replaced.
public protocol BulgarianLexicon: Sendable {
    /// `nil` when the lexicon cannot answer (unavailable or timed out). Callers must then leave the word alone.
    func isKnownWord(_ word: String) async -> Bool?
}

/// Uses the macOS Bulgarian spelling dictionary.
public struct SystemBulgarianLexicon: BulgarianLexicon {
    public init() {}

    public func isKnownWord(_ word: String) async -> Bool? {
        await MainActor.run {
            let checker = NSSpellChecker.shared
            guard checker.availableLanguages.contains("bg") else { return nil }
            let range = checker.checkSpelling(of: word, startingAt: 0, language: "bg", wrap: false,
                                              inSpellDocumentWithTag: 0, wordCount: nil)
            return range.location == NSNotFound
        }
    }

    /// The spelling server is slow on its first query; call this at launch so dictation never waits on it.
    public static func warmUp() {
        Task { @MainActor in
            _ = NSSpellChecker.shared.checkSpelling(of: "проверка", startingAt: 0, language: "bg", wrap: false,
                                                    inSpellDocumentWithTag: 0, wordCount: nil)
        }
    }
}

/// Restores vocabulary terms that speech recognition spelled phonetically or wrongly.
///
/// Conservative by design:
/// 1. Exact alias matches (from the user-editable vocabulary).
/// 2. Phonetic matches, only for Cyrillic words that the Bulgarian dictionary does *not* know,
///    only against vocabulary terms, and only above a high similarity threshold.
/// A genuine Bulgarian word ("компонент", "сървър") is never turned into English.
public struct TermRepairer: Sendable {
    public struct Replacement: Sendable, Equatable {
        public var original: String
        public var replacement: String
    }

    public var entries: [VocabularyEntry]
    public var lexicon: (any BulgarianLexicon)?
    public var threshold: Double

    public init(entries: [VocabularyEntry], lexicon: (any BulgarianLexicon)? = SystemBulgarianLexicon(), threshold: Double = 0.8) {
        self.entries = entries.filter(\.enabled)
        self.lexicon = lexicon
        self.threshold = threshold
    }

    /// Definite-article and plural endings Bulgarian attaches to borrowed English terms.
    static let suffixes = ["овете", "ите", "ове", "ът", "ят", "та", "то", "те", "а", "я", "и"]

    public func repair(_ text: String) async -> (text: String, replacements: [Replacement]) {
        var result = text
        var replacements: [Replacement] = []
        let dominant = TextScript.dominant(in: text)

        // 1. Aliases, longest first so "клод код" wins over "клод".
        let aliasPairs = entries
            .filter { applies($0, to: dominant) }
            .flatMap { entry in entry.aliases.map { (alias: $0, term: entry.term) } }
            .sorted { $0.alias.count > $1.alias.count }
        for pair in aliasPairs {
            result = replaceAlias(pair.alias, with: pair.term, in: result, log: &replacements)
        }

        // 2. Phonetic restoration of unknown Cyrillic words in Bulgarian speech.
        guard dominant == .bulgarian || dominant == .mixed, let lexicon else { return (result, replacements) }
        let candidates = entries.filter { $0.matchPhonetically && $0.scope != .english && !$0.term.contains(" ") }
        guard !candidates.isEmpty else { return (result, replacements) }

        var output = ""
        var cursor = result.startIndex
        for range in Self.cyrillicWordRanges(in: result) {
            output += result[cursor..<range.lowerBound]
            let word = String(result[range])
            if let fixed = await phoneticRepair(word, candidates: candidates, lexicon: lexicon) {
                output += fixed
                replacements.append(Replacement(original: word, replacement: fixed))
            } else {
                output += word
            }
            cursor = range.upperBound
        }
        output += result[cursor...]
        return (output, replacements)
    }

    private func applies(_ entry: VocabularyEntry, to dominant: TextScript.Dominant) -> Bool {
        switch entry.scope {
        case .any: true
        case .english: dominant == .english || dominant == .mixed
        case .bulgarian: dominant == .bulgarian || dominant == .mixed
        }
    }

    private func replaceAlias(_ alias: String, with term: String, in text: String, log: inout [Replacement]) -> String {
        let cyrillic = alias.unicodeScalars.contains(where: TextScript.isCyrillic)
        let body = NSRegularExpression.escapedPattern(for: alias).replacingOccurrences(of: "\\ ", with: "\\s+")
        let suffix = cyrillic ? "(\(Self.suffixes.joined(separator: "|")))?" : "()"
        let pattern = "(?<![\\p{L}\\p{N}])\(body)\(suffix)(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        var out = ""
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text) else { continue }
            var ending = ""
            if let r = Range(match.range(at: 1), in: text) { ending = String(text[r]) }
            let replacement = ending.isEmpty ? term : "\(term)-\(ending)"
            out += text[cursor..<whole.lowerBound] + replacement
            log.append(Replacement(original: String(text[whole]), replacement: replacement))
            cursor = whole.upperBound
        }
        out += text[cursor...]
        return out
    }

    private func phoneticRepair(_ word: String, candidates: [VocabularyEntry], lexicon: any BulgarianLexicon) async -> String? {
        let lower = word.lowercased()
        guard lower.count >= 3 else { return nil }
        // Try the bare word first, then with a Bulgarian ending split off.
        var forms: [(stem: String, ending: String)] = [(lower, "")]
        for suffix in Self.suffixes where lower.hasSuffix(suffix) && lower.count - suffix.count >= 4 {
            forms.append((String(lower.dropLast(suffix.count)), suffix))
        }
        var best: (term: String, ending: String, score: Double)?
        for form in forms {
            let key = Phonetic.key(Phonetic.transliterate(form.stem))
            for entry in candidates {
                let termKey = Phonetic.key(entry.term.lowercased())
                guard key.first == termKey.first else { continue }
                // Short keys must match exactly; longer ones may differ slightly.
                let score = (key.count <= 4 || termKey.count <= 4)
                    ? (key == termKey ? 1 : 0)
                    : Phonetic.similarity(key, termKey)
                if score >= threshold, score > (best?.score ?? 0) {
                    best = (entry.term, form.ending, score)
                }
            }
        }
        guard let best else { return nil }
        // Only now ask the dictionary: a genuine Bulgarian word is left untouched, and so is
        // anything the lexicon cannot vouch for.
        guard let known = await lexicon.isKnownWord(lower), !known else { return nil }
        return best.ending.isEmpty ? best.term : "\(best.term)-\(best.ending)"
    }

    static func cyrillicWordRanges(in text: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: "[\\p{Script=Cyrillic}]+") else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
    }
}

/// Rough cross-language phonetic keys so "дешбод" and "dashboard" compare as the same sound.
enum Phonetic {
    static let cyrillicToLatin: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ж": "zh", "з": "z", "и": "i", "й": "y",
        "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
        "ф": "f", "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sht", "ъ": "a", "ь": "y", "ю": "yu", "я": "ya",
    ]

    static func transliterate(_ text: String) -> String {
        text.lowercased().map { cyrillicToLatin[$0] ?? String($0) }.joined()
    }

    /// Normalises spelling to approximate pronunciation, then collapses vowels (vowel quality is the
    /// least reliable part of cross-language transcription).
    static func key(_ latin: String) -> String {
        var s = latin.lowercased().filter { $0.isLetter }
        if s.count > 3, s.hasSuffix("e"), let beforeLast = s.dropLast().last, !"aeiouy".contains(beforeLast) {
            s.removeLast() // silent final e: "claude" → "claud"
        }
        let rules: [(String, String)] = [
            ("tion", "shan"), ("ph", "f"), ("ck", "k"), ("th", "t"), ("qu", "kv"), ("q", "k"), ("x", "ks"),
            ("w", "v"), ("dzh", "J"), ("j", "J"), ("sh", "S"), ("zh", "Z"), ("ch", "C"), ("ts", "c"),
            ("ce", "se"), ("ci", "si"), ("cy", "sy"), ("c", "k"),
        ]
        for (from, to) in rules { s = s.replacingOccurrences(of: from, with: to) }
        // Non-rhotic r before a consonant or at the end ("board" is heard as "бод").
        var chars = Array(s)
        var out: [Character] = []
        for (i, ch) in chars.enumerated() {
            if ch == "r", i > 0, "aeiouy".contains(chars[i - 1]), i == chars.count - 1 || !"aeiouy".contains(chars[i + 1]) {
                continue
            }
            out.append(ch)
        }
        chars = out
        // Vowels → "a", collapse runs and doubled letters.
        var key = ""
        for ch in chars {
            let c: Character = "aeiouy".contains(ch) ? "a" : ch
            if key.last != c { key.append(c) }
        }
        return key
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        guard !x.isEmpty || !y.isEmpty else { return 1 }
        var previous = Array(0...y.count)
        for i in 1...max(x.count, 1) where !x.isEmpty {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in 1...max(y.count, 1) where !y.isEmpty {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[y.count]) / Double(max(x.count, y.count))
    }
}
