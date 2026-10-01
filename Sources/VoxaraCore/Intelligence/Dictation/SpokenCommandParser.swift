import Foundation

/// Converts a small, fixed set of spoken formatting commands into text.
///
/// This is intentionally a lookup table, not NLP. Commands are only recognised when they
/// stand alone as whole words, and punctuation commands are replaced in place.
public enum SpokenCommandParser {
    private struct Command {
        let phrase: String
        let output: String
        /// How surrounding whitespace is handled around the inserted text.
        let attach: Attach
    }

    private enum Attach {
        case left      // "," "." — glued to the previous word
        case both      // newline — no spaces around
        case opening   // opening quote — glued to the next word
        case closing   // closing quote — glued to the previous word
    }

    // Longest phrases first so "new paragraph" wins over "new".
    private static let english: [Command] = [
        Command(phrase: "new paragraph", output: "\n\n", attach: .both),
        Command(phrase: "next paragraph", output: "\n\n", attach: .both),
        Command(phrase: "new line", output: "\n", attach: .both),
        Command(phrase: "newline", output: "\n", attach: .both),
        Command(phrase: "next line", output: "\n", attach: .both),
        Command(phrase: "question mark", output: "?", attach: .left),
        Command(phrase: "exclamation mark", output: "!", attach: .left),
        Command(phrase: "exclamation point", output: "!", attach: .left),
        Command(phrase: "full stop", output: ".", attach: .left),
        Command(phrase: "semicolon", output: ";", attach: .left),
        Command(phrase: "semi colon", output: ";", attach: .left),
        Command(phrase: "colon", output: ":", attach: .left),
        Command(phrase: "comma", output: ",", attach: .left),
        Command(phrase: "period", output: ".", attach: .left),
        Command(phrase: "open quote", output: "\u{201C}", attach: .opening),
        Command(phrase: "close quote", output: "\u{201D}", attach: .closing),
        Command(phrase: "end quote", output: "\u{201D}", attach: .closing),
        Command(phrase: "open parenthesis", output: "(", attach: .opening),
        Command(phrase: "close parenthesis", output: ")", attach: .closing),
    ]

    private static let bulgarian: [Command] = [
        Command(phrase: "нов абзац", output: "\n\n", attach: .both),
        Command(phrase: "нов параграф", output: "\n\n", attach: .both),
        Command(phrase: "нов ред", output: "\n", attach: .both),
        Command(phrase: "въпросителен знак", output: "?", attach: .left),
        Command(phrase: "удивителна", output: "!", attach: .left),
        Command(phrase: "точка и запетая", output: ";", attach: .left),
        Command(phrase: "двоеточие", output: ":", attach: .left),
        Command(phrase: "запетая", output: ",", attach: .left),
        Command(phrase: "отвори кавички", output: "\u{201E}", attach: .opening),
        Command(phrase: "затвори кавички", output: "\u{201C}", attach: .closing),
    ]

    /// Bulgarian "точка" is also an everyday noun ("точка на продажба"), so it is only
    /// treated as punctuation when it is the sentence-final word, standing alone.
    private static let bulgarianFinalPeriod = "точка"

    public static func apply(to text: String) -> String {
        var result = text
        let dominant = TextScript.dominant(in: text)
        for command in english { result = replace(command, in: result) }
        if dominant == .bulgarian || dominant == .mixed {
            for command in bulgarian { result = replace(command, in: result) }
            result = replaceTrailing(bulgarianFinalPeriod, with: ".", in: result)
        }
        return tidy(result)
    }

    private static func replace(_ command: Command, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: command.phrase).replacingOccurrences(of: "\\ ", with: "\\s+")
        // Optional punctuation the STT engine already added around the phrase ("comma," / "Comma.").
        let pattern = "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])[,.]?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        var out = ""
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            var before = String(text[cursor..<r.lowerBound])
            switch command.attach {
            case .left, .closing, .both:
                while before.last == " " { before.removeLast() }
                // "Hello, comma" → the STT already added a comma; don't double it.
                if command.attach == .left, let last = before.last, ",.;:?!".contains(last) { before.removeLast() }
            case .opening:
                break
            }
            out += before
            out += command.output
            cursor = r.upperBound
            switch command.attach {
            case .both, .opening, .left, .closing:
                break
            }
            // Swallow whitespace after commands that attach on both sides or open something.
            if command.attach == .both || command.attach == .opening {
                while cursor < text.endIndex, text[cursor] == " " { cursor = text.index(after: cursor) }
            }
        }
        out += String(text[cursor...])
        return out
    }

    private static func replaceTrailing(_ word: String, with symbol: String, in text: String) -> String {
        let pattern = "\\s*(?<![\\p{L}\\p{N}])\(word)[.!]?\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), let r = Range(match.range, in: text) else { return text }
        let before = String(text[..<r.lowerBound])
        // Only when it is clearly a command: something sensible precedes it.
        guard before.split(whereSeparator: \.isWhitespace).count >= 2 else { return text }
        return before + symbol
    }

    /// Normalises whitespace and punctuation spacing after substitutions.
    static func tidy(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: " ([,.;:?!])", with: "$1", options: .regularExpression)
        // Space after sentence punctuation when a letter follows directly ("word.Next" → "word. Next"),
        // but leave decimals, versions and domains alone (digits / lowercase continuations).
        s = s.replacingOccurrences(of: "([,;:?!])(?=[\\p{L}])", with: "$1 ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?<=[\\p{Ll}\\d])(\\.)(?=[\\p{Lu}][\\p{Ll}])", with: "$1 ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }
}
