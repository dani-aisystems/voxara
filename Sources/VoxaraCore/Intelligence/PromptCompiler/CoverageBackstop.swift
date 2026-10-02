import Foundation

/// Safety net against a weak model silently dropping something the speaker said.
/// Any spoken clause whose content is absent from the finished prompt is appended verbatim
/// (cleaned) under "Also mentioned", so detail is kept even when extraction misses it.
public enum CoverageBackstop {
    /// Everyday words that carry no task content, so a clause made only of them can be ignored.
    static let fluff: Set<String> = [
        "okay", "done", "finished", "finish", "youre", "you're", "basically", "obviously", "definitely", "certainly", "literally", "honestly", "actually", "really", "just", "thing", "things", "bit", "long", "want", "wants",
        "need", "needs", "like", "would", "could", "please", "think", "maybe", "probably", "kind", "sort", "something",
        "anything", "everything", "stuff", "some", "very", "much", "make", "sure", "what", "when", "where", "does",
        "have", "know", "going", "doing", "good", "better", "right", "fine", "tell", "give", "take", "look", "looks",
        "yeah", "well", "gonna", "wanna", "also", "still", "even", "ever", "never", "about", "because", "though", "while",
        "искам", "трябва", "просто", "всъщност", "наистина", "малко", "нещо", "неща", "може", "бих", "добре", "ами",
        "значи", "такова", "както", "защото", "така", "много", "къде", "кога", "какво",
    ]

    public static func missingClauses(transcript: String, prompt: String) -> [String] {
        let promptWords = TextScript.words(stripScaffolding(prompt))
        var missing: [String] = []
        for clause in clauses(in: transcript) {
            let content = TextScript.words(clause).filter {
                $0.count >= 4 && !GroundingChecker.stopwords.contains($0) && !fluff.contains($0)
            }
            guard content.count >= 2 else { continue }
            let hits = content.filter { word in promptWords.contains { GroundingChecker.sameWord($0, word) } }.count
            if Double(hits) / Double(content.count) < 0.5 { missing.append(tidy(clause)) }
        }
        return missing
    }

    /// Removes what the prompt adds itself (XML tags, section labels, markdown headings) so those words are not
    /// mistaken for words the speaker said.
    static func stripScaffolding(_ prompt: String) -> String {
        var s = prompt.replacingOccurrences(of: "</?[A-Za-z_]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?m)^\\s*#+\\s+.*$", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?m)^[^\\n.]{1,40}:\\s*$", with: " ", options: .regularExpression)
        return s
    }

    static func clauses(in text: String) -> [String] {
        // Sentence ends, commas, and clause-level conjunctions. Splitting at "but" / "because" matters: one long spoken
        // sentence often carries several separate instructions, and a few matching words must not hide a dropped one.
        let pattern = "(?:[.!?;]+\\s+|,\\s*(?:and|but|so|then|also|because|while|и|но|а|че|защото|после)?\\s+|\\s+(?:and then|but then|but|because|so that|although|however|но|защото|и после)\\s+)"
        let marked = text.replacingOccurrences(of: pattern, with: "\u{1F}", options: [.regularExpression, .caseInsensitive])
        let first = marked.split(separator: "\u{1F}").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        // Long clauses often chain separate instructions with "and"; judge those parts separately.
        return first.flatMap { clause -> [String] in
            guard clause.split(whereSeparator: \.isWhitespace).count > 6 else { return [clause] }
            return clause.replacingOccurrences(of: "\\s+(?:and|и)\\s+", with: "\u{1F}", options: [.regularExpression, .caseInsensitive])
                .split(separator: "\u{1F}").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
    }

    static func tidy(_ clause: String) -> String {
        var s = clause.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:"))
        for lead in ["and ", "but ", "so ", "then ", "also ", "и ", "но ", "а ", "че "] where s.lowercased().hasPrefix(lead) {
            s = String(s.dropFirst(lead.count))
        }
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst() + "."
    }
}
