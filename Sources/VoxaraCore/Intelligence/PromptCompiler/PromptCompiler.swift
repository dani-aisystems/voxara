import Foundation

/// Prompt Mode: turns a messy spoken request into a well-structured prompt for a chosen destination.
///
/// Pipeline: normalize (rules + vocabulary) → extract intent (local model, schema-constrained)
/// → ground (drop anything not traceable to the speech) → render (profile + preset) → verify.
/// If the model is unavailable or verification keeps failing, a structured-lite prompt is built from
/// the cleaned transcript itself, so the user's words are never lost.
public struct PromptCompiler: Sendable {
    public struct Outcome: Sendable {
        public var prompt: String
        public var usedModel: Bool
        public var notice: String?
        public var dropped: [String]
        public var spec: IntentSpec?
        /// Verification problems seen on the last attempt (debugging aid).
        public var problems: [String] = []
    }

    public var provider: (any AIProvider)?
    public var profiles: ProfileStore
    public var cleaner = DeterministicCleaner()
    public var renderer = PromptRenderer()
    public var grounding = GroundingChecker()
    public var timeout: TimeInterval = 25

    public init(provider: (any AIProvider)?, profiles: ProfileStore, timeout: TimeInterval = 25) {
        self.provider = provider
        self.profiles = profiles
        self.timeout = timeout
    }

    public func compile(transcript raw: String, profileID: String, preset: PromptPreset,
                        outputLanguage: PromptOutputLanguage = .sameAsSpeech) async -> Outcome {
        let profile = profiles.profile(profileID)
        let presetConfig = profiles.preset(preset)
        let transcript = cleaner.clean(raw)
        let spoken: String = TextScript.dominant(in: transcript) == .bulgarian ? "bg" : "en"
        let language = outputLanguage == .english ? "en" : spoken
        // Cross-language output cannot be word-grounded against the transcript; anchors still apply.
        let wordGrounding = language == spoken
        let anchors = PromptAnchors.extract(from: transcript)
        let hadCorrection = SelfCorrectionDetector.hasCorrection(in: transcript)

        guard let provider else {
            return fallback(transcript, profile: profile, preset: preset, config: presetConfig, language: language,
                            notice: "No AI model configured — built a basic prompt")
        }

        let extractor = IntentExtractor(provider: provider, timeout: timeout)
        let writeIn = language == "en" ? "English" : "same language as transcript (Bulgarian)"
        var feedback: String?
        var lastDropped: [String] = []
        var lastProblems: [String] = []

        for attempt in 0..<2 {
            let spec: IntentSpec
            do {
                spec = try await extractor.extract(transcript: transcript, writeIn: writeIn, hints: profile.extractorHints, feedback: feedback)
            } catch {
                return fallback(transcript, profile: profile, preset: preset, config: presetConfig, language: language,
                                notice: "AI model unavailable — built a basic prompt")
            }
            let report = grounding.ground(Self.sanitize(spec), transcript: transcript, checkWords: wordGrounding)
            lastDropped = report.dropped
            var prompt = renderer.render(spec: report.spec, profile: profile, preset: preset, presetConfig: presetConfig,
                                         transcript: transcript, language: language)
            prompt = Self.appendMissing(to: prompt, transcript: transcript, language: language, style: profile.style.heading)

            let problems = verify(prompt: prompt, transcript: transcript, anchors: anchors, hadCorrection: hadCorrection)
            lastProblems = problems
            if problems.isEmpty, !report.spec.objective.isEmpty {
                return Outcome(prompt: prompt, usedModel: true, notice: nil, dropped: lastDropped, spec: report.spec)
            }
            feedback = problems.isEmpty ? "The objective was missing; state it." : problems.joined(separator: " ")
            if attempt == 1 {
                return fallback(transcript, profile: profile, preset: preset, config: presetConfig, language: language,
                                notice: "Prompt check failed — built a basic prompt from your words", dropped: lastDropped,
                                problems: lastProblems)
            }
        }
        return fallback(transcript, profile: profile, preset: preset, config: presetConfig, language: language, notice: nil)
    }

    // MARK: - Verification

    func verify(prompt: String, transcript: String, anchors: [String], hadCorrection: Bool) -> [String] {
        var problems: [String] = []
        let missing = PromptAnchors.missing(anchors, in: prompt)
        // After a spoken self-correction, the corrected-away value is legitimately absent.
        let allowed = hadCorrection ? Int(Double(anchors.count) * 0.25) : 0
        if missing.count > allowed {
            problems.append("The result must keep these terms exactly as spoken: \(missing.joined(separator: ", ")).")
        }
        let invented = PromptAnchors.inventedNumbers(in: Self.stripListMarkers(prompt), transcript: transcript)
        if !invented.isEmpty {
            problems.append("These numbers were not spoken, remove them: \(invented.joined(separator: ", ")).")
        }
        return problems
    }

    static func stripListMarkers(_ prompt: String) -> String {
        prompt.replacingOccurrences(of: "(?m)^\\s*(?:\\d+\\.|-)\\s+", with: "", options: .regularExpression)
    }

    // MARK: - Fallback

    /// Structured-lite: the speaker's own cleaned words inside the profile's framing. Never invents anything.
    func fallback(_ transcript: String, profile: PromptProfile, preset: PromptPreset, config: PresetConfig,
                  language: String, notice: String?, dropped: [String] = [], problems: [String] = []) -> Outcome {
        var spec = IntentSpec(objective: "")
        let sentences = Self.sentences(in: transcript)
        spec.objective = sentences.first ?? transcript
        spec.requirements = Array(sentences.dropFirst())
        var lite = config
        if config.compact { lite.sections = ["requirements"] }
        let prompt = renderer.render(spec: spec, profile: profile, preset: preset, presetConfig: lite,
                                     transcript: transcript, language: language)
        return Outcome(prompt: prompt, usedModel: false, notice: notice, dropped: dropped, spec: nil, problems: problems)
    }

    /// Drops junk the model sometimes emits as list items (bare brackets, punctuation) and trims whitespace.
    static func sanitize(_ spec: IntentSpec) -> IntentSpec {
        func useful(_ item: String) -> Bool { item.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count >= 3 }
        var result = spec
        for section in IntentSpec.sections {
            result[section] = spec[section].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter(useful)
        }
        return result
    }

    /// Appends spoken clauses the prompt lost, in the profile's heading style.
    static func appendMissing(to prompt: String, transcript: String, language: String, style: String) -> String {
        // Cross-language output cannot be compared word for word; skip rather than add untranslated text.
        guard (TextScript.dominant(in: transcript) == .bulgarian) == (language == "bg") else { return prompt }
        let missing = CoverageBackstop.missingClauses(transcript: transcript, prompt: prompt)
        guard !missing.isEmpty else { return prompt }
        let label = language == "bg" ? "Също казано" : "Also mentioned"
        let items = missing.map { "- \($0)" }.joined(separator: "\n")
        let block: String
        switch style {
        case "xml": block = "<also_mentioned>\n\(items)\n</also_mentioned>"
        case "markdown": block = "## \(label)\n\(items)"
        default: block = "\(label):\n\(items)"
        }
        return prompt + "\n\n" + block
    }

    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sub, _, _, _ in
            if let sub = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty { result.append(sub) }
        }
        return result
    }
}
