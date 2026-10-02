import Foundation

/// Builds the final prompt text from an `IntentSpec`, a destination profile and a preset.
/// Deterministic: the same inputs always give the same output, so it is fully unit-testable.
public struct PromptRenderer: Sendable {
    public init() {}

    /// `language` is "en" or "bg" and selects section labels and the wording of profile signal lines.
    public func render(spec: IntentSpec, profile: PromptProfile, preset: PromptPreset, presetConfig: PresetConfig,
                       transcript: String, language: String) -> String {
        var spec = spec
        if presetConfig.signals {
            applySignals(to: &spec, profile: profile, preset: preset, transcript: transcript, language: language)
        }
        let objective = spec.objective.trimmingCharacters(in: .whitespacesAndNewlines)

        if presetConfig.compact {
            return renderCompact(spec: spec, objective: objective, sections: presetConfig.sections)
        }

        var blocks: [String] = []
        if !objective.isEmpty { blocks.append(objective) }
        let numberWorkflow = profile.style.numberedWorkflow || presetConfig.numberWorkflow == true
        for section in profile.sectionOrder where presetConfig.sections.contains(section) {
            let items = spec[section].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !items.isEmpty else { continue }
            blocks.append(block(section: section, items: items, profile: profile, language: language,
                                numbered: section == "workflow" && numberWorkflow && items.count > 1))
        }
        return blocks.joined(separator: "\n\n")
    }

    // MARK: - Pieces

    private func block(section: String, items: [String], profile: PromptProfile, language: String, numbered: Bool) -> String {
        let label = profile.label(section, language: language)
        let lines = items.enumerated().map { index, item in numbered ? "\(index + 1). \(item)" : "- \(item)" }
        // A single deliverable reads better as a sentence than as a one-item list.
        let body = section == "deliverable" && items.count == 1 ? items[0] : lines.joined(separator: "\n")
        switch profile.style.heading {
        case "xml":
            let tag = Self.tagName(section)
            return "<\(tag)>\n\(body)\n</\(tag)>"
        case "markdown":
            return "## \(label)\n\(body)"
        default:
            return "\(label):\n\(body)"
        }
    }

    private func renderCompact(spec: IntentSpec, objective: String, sections: [String]) -> String {
        var parts: [String] = []
        if !objective.isEmpty { parts.append(Self.sentence(objective)) }
        for section in sections {
            for item in spec[section] {
                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { parts.append(Self.sentence(trimmed)) }
            }
        }
        return parts.joined(separator: " ")
    }

    private func applySignals(to spec: inout IntentSpec, profile: PromptProfile, preset: PromptPreset,
                              transcript: String, language: String) {
        let lower = transcript.lowercased()
        for signal in profile.signals where signal.presets.contains(preset.rawValue) {
            guard signal.triggers.contains(where: { lower.contains($0.lowercased()) }) else { continue }
            guard let text = signal.text[language] ?? signal.text["en"] else { continue }
            var items = spec[signal.section]
            // Skip when the extracted spec already says essentially the same thing.
            if items.contains(where: { Self.overlap($0, text) >= 0.6 }) { continue }
            // Signal lines come first within their section: they frame the speaker's own items.
            if signal.section == "validation" || signal.section == "done" || signal.section == "constraints" {
                items.append(text)
            } else {
                items.insert(text, at: 0)
            }
            spec[signal.section] = items
        }
    }

    static func overlap(_ a: String, _ b: String) -> Double {
        let x = Set(TextScript.words(a).filter { $0.count > 3 }.map(GroundingChecker.stem))
        let y = Set(TextScript.words(b).filter { $0.count > 3 }.map(GroundingChecker.stem))
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        return Double(x.intersection(y).count) / Double(min(x.count, y.count))
    }

    static func tagName(_ section: String) -> String {
        switch section {
        case "workflow": "approach"
        case "exclusions": "do_not"
        case "done": "done_when"
        default: section
        }
    }

    static func sentence(_ text: String) -> String {
        guard let last = text.last else { return text }
        return ".!?…:;".contains(last) ? text : text + "."
    }
}

/// Facts from the transcript that a compiled prompt must not lose or contradict.
public enum PromptAnchors {
    /// Numbers, Latin-script terms inside Cyrillic speech, and mid-sentence capitalised names.
    public static func extract(from transcript: String) -> [String] {
        var anchors: [String] = []
        var seen = Set<String>()
        func add(_ value: String) { if seen.insert(value.lowercased()).inserted { anchors.append(value) } }

        for number in OutputGuards.numbers(in: transcript) { add(number) }
        if TextScript.dominant(in: transcript) != .english {
            for term in OutputGuards.latinTerms(in: transcript) where term.count >= 3 { add(term) }
        }
        for name in properNouns(in: transcript) where !isDestination(name) { add(name) }
        return anchors.filter { !isDestination($0) }
    }

    /// The AI the prompt is written *for* is the reader, not part of the task, so it may be omitted.
    static let destinations: Set<String> = ["claude", "code", "chatgpt", "gpt", "gemini", "codex", "copilot", "claude code", "openai", "anthropic"]

    static func isDestination(_ term: String) -> Bool {
        destinations.contains(term.lowercased())
    }

    /// Capitalised words that are not the first word of a sentence ("Citizens Club", "Catalea", "Maria").
    static func properNouns(in text: String) -> [String] {
        var names: [String] = []
        var atSentenceStart = true
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let word = String(token).trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "-.")))
            let clean = word.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
            if !atSentenceStart, clean.count >= 3, let first = clean.first, first.isUppercase,
               clean.dropFirst().contains(where: \.isLowercase), !isPronounContraction(clean) {
                names.append(clean)
            }
            atSentenceStart = token.last.map { ".!?".contains($0) } ?? false
        }
        return names
    }

    /// "I'm", "I'll", "I'd", "I've" are capitalised but are not names.
    static func isPronounContraction(_ word: String) -> Bool {
        word == "I" || word.hasPrefix("I'") || word.hasPrefix("I’")
    }

    public static func missing(_ anchors: [String], in prompt: String) -> [String] {
        let lower = prompt.lowercased()
        return anchors.filter { !lower.contains($0.lowercased()) }
    }

    /// Numbers in the prompt that the speaker never said.
    public static func inventedNumbers(in prompt: String, transcript: String) -> [String] {
        let spoken = Set(OutputGuards.numbers(in: transcript)).union(spokenNumberWords(in: transcript))
        return OutputGuards.numbers(in: prompt).filter { !spoken.contains($0) }
    }

    /// Digits for number words the speaker said ("three" → "3"), so rewriting "three clients" as "3 clients" is not flagged.
    static func spokenNumberWords(in text: String) -> Set<String> {
        let table: [String: String] = [
            "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7",
            "eight": "8", "nine": "9", "ten": "10", "eleven": "11", "twelve": "12", "twenty": "20", "thirty": "30",
            "fifty": "50", "hundred": "100", "thousand": "1000", "first": "1", "second": "2", "third": "3",
            "нула": "0", "един": "1", "една": "1", "едно": "1", "два": "2", "две": "2", "три": "3", "четири": "4",
            "пет": "5", "шест": "6", "седем": "7", "осем": "8", "девет": "9", "десет": "10", "двадесет": "20",
            "петдесет": "50", "сто": "100", "хиляда": "1000", "първи": "1", "втори": "2", "трети": "3",
        ]
        return Set(TextScript.words(text).compactMap { table[$0] })
    }
}
