import Foundation

/// Script and language heuristics shared by the cleaner, the output guards and the prompt compiler.
public enum TextScript {
    public static func isCyrillic(_ scalar: Unicode.Scalar) -> Bool {
        (0x0400...0x04FF).contains(scalar.value) || (0x0500...0x052F).contains(scalar.value)
    }

    public static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
            || (0xC0...0x24F).contains(scalar.value)
    }

    public struct Counts: Sendable, Equatable {
        public var cyrillic = 0
        public var latin = 0
        public var letters: Int { cyrillic + latin }
    }

    public static func counts(in text: String) -> Counts {
        var c = Counts()
        for scalar in text.unicodeScalars {
            if isCyrillic(scalar) { c.cyrillic += 1 } else if isLatinLetter(scalar) { c.latin += 1 }
        }
        return c
    }

    public enum Dominant: Sendable, Equatable { case bulgarian, english, mixed, none }

    /// Dominant script of the letters in `text`. Anything with a meaningful Cyrillic share is Bulgarian-dominant
    /// because Latin tech terms commonly appear inside Bulgarian sentences.
    public static func dominant(in text: String) -> Dominant {
        let c = counts(in: text)
        guard c.letters > 0 else { return .none }
        let cyrillicShare = Double(c.cyrillic) / Double(c.letters)
        if cyrillicShare > 0.6 { return .bulgarian }
        if cyrillicShare < 0.05 { return .english }
        return .mixed
    }

    /// Words (letters/digits/apostrophes/hyphens), lowercased, for overlap and grounding checks.
    public static func words(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "'" || ch == "’" || ch == "-" {
                current.append(ch)
            } else if !current.isEmpty {
                result.append(current.trimmingCharacters(in: CharacterSet(charactersIn: "'’-")))
                current = ""
            }
        }
        if !current.isEmpty { result.append(current.trimmingCharacters(in: CharacterSet(charactersIn: "'’-"))) }
        return result.filter { !$0.isEmpty }
    }
}
