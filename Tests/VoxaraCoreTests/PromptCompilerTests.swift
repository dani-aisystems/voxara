import Foundation
import Testing
@testable import VoxaraCore

private func specJSON(_ spec: IntentSpec) -> String {
    let data = try! JSONEncoder().encode(spec)
    return String(data: data, encoding: .utf8)!
}

private func store() throws -> ProfileStore { try ProfileStore.load(userDirectory: nil) }

@Suite struct ProfileStoreTests {
    @Test func loadsAllFourProfilesAndPresets() throws {
        let s = try store()
        #expect(Set(s.profiles.keys).isSuperset(of: ["generic", "claude", "chatgpt", "claude-code"]))
        for preset in PromptPreset.allCases { #expect(!s.preset(preset).sections.isEmpty) }
    }

    @Test func everyProfileIsCompleteInBothLanguages() throws {
        for profile in try store().ordered {
            #expect(!profile.philosophy.isEmpty, "\(profile.id) philosophy")
            #expect(!profile.forbidden.isEmpty, "\(profile.id) forbidden")
            for section in IntentSpec.sections {
                #expect(profile.labels["en"]?[section] != nil, "\(profile.id) en label \(section)")
                #expect(profile.labels["bg"]?[section] != nil, "\(profile.id) bg label \(section)")
            }
            for signal in profile.signals {
                #expect(!signal.triggers.isEmpty, "\(profile.id).\(signal.id) triggers")
                #expect(signal.text["en"] != nil && signal.text["bg"] != nil, "\(profile.id).\(signal.id) text")
                #expect(IntentSpec.sections.contains(signal.section), "\(profile.id).\(signal.id) section")
            }
        }
    }

    @Test func userProfileOverridesBundledOne() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vx-profiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var custom = try store().profile("generic")
        custom.name = "My Generic"
        try JSONEncoder().encode(custom).write(to: dir.appendingPathComponent("generic.json"))
        #expect(try ProfileStore.load(userDirectory: dir).profile("generic").name == "My Generic")
    }

    @Test func unknownProfileFallsBackToGeneric() throws {
        #expect(try store().profile("nope").id == "generic")
    }
}

@Suite struct PromptRendererTests {
    private let renderer = PromptRenderer()
    private let spec = IntentSpec(
        objective: "Improve the mobile hero.", context: ["The hero looks wrong on mobile."],
        workflow: ["Check how it is built.", "Then change it."], requirements: ["Make the CTA more visible."],
        exclusions: ["Do not change desktop."], validation: ["Make sure nothing else broke."]
    )

    private func render(_ profile: String, _ preset: PromptPreset, transcript: String = "", language: String = "en") throws -> String {
        let s = try store()
        return renderer.render(spec: spec, profile: s.profile(profile), preset: preset, presetConfig: s.preset(preset),
                               transcript: transcript, language: language)
    }

    @Test func headingStylesDifferByProfile() throws {
        #expect(try render("generic", .structured).contains("Requirements:\n- Make the CTA more visible."))
        #expect(try render("chatgpt", .structured).contains("## Requirements\n- Make the CTA more visible."))
        #expect(try render("claude", .structured).contains("<requirements>\n- Make the CTA more visible.\n</requirements>"))
    }

    @Test func claudeCodeNumbersTheWorkflow() throws {
        let out = try render("claude-code", .structured)
        #expect(out.contains("1. Check how it is built."))
        #expect(out.contains("2. Then change it."))
    }

    @Test func emptySectionsAreOmitted() throws {
        let out = try render("generic", .structured)
        #expect(!out.contains("References"))
        #expect(!out.contains("Research"))
    }

    @Test func objectiveComesFirstWithoutLabel() throws {
        #expect(try render("generic", .structured).hasPrefix("Improve the mobile hero."))
    }

    @Test func bulgarianLabelsAreUsed() throws {
        let out = try render("generic", .structured, language: "bg")
        #expect(out.contains("Изисквания:"))
    }

    @Test func quickIsCompactWithoutHeadings() throws {
        let out = try render("claude-code", .quick)
        #expect(!out.contains("Requirements:"))
        #expect(!out.contains("<"))
        #expect(out.contains("Make the CTA more visible."))
        #expect(out.contains("Do not change desktop."))
    }

    @Test func signalsAddLinesOnlyWhenTriggered() throws {
        let plain = try render("claude-code", .structured, transcript: "rename the button to Save")
        #expect(!plain.contains("project's own checks"))
        let triggered = try render("claude-code", .structured, transcript: "fix it and run the tests afterwards")
        #expect(triggered.contains("project's own checks"))
    }

    @Test func genericProfileDoesNotGetCodingBoilerplate() throws {
        let out = try render("generic", .structured, transcript: "investigate why it is slow and run the tests")
        #expect(!out.contains("lint"))
        #expect(!out.contains("root cause"))
    }

    @Test func deepOnlySignalsAppearOnlyInDeep() throws {
        let transcript = "investigate the bug and fix it"
        #expect(!(try render("claude-code", .structured, transcript: transcript).contains("Do not stop until")))
        #expect(try render("claude-code", .deep, transcript: transcript).contains("Do not stop until"))
    }

    @Test func signalIsSkippedWhenSpecAlreadySaysIt() throws {
        var s2 = spec
        s2.workflow = ["Inspect the relevant code and how it currently works before changing anything."]
        let store = try store()
        let out = renderer.render(spec: s2, profile: store.profile("claude-code"), preset: .structured,
                                  presetConfig: store.preset(.structured), transcript: "inspect it first", language: "en")
        #expect(out.components(separatedBy: "Inspect the relevant code").count == 2)
    }
}

@Suite struct GroundingTests {
    private let grounding = GroundingChecker()

    @Test func dropsItemsNotTracedToTheSpeech() {
        let spec = IntentSpec(objective: "Fix the checkout page.", requirements: ["Use React and Tailwind for the layout."],
                              exclusions: ["Do not touch the checkout page."])
        let report = grounding.ground(spec, transcript: "fix the checkout page but do not touch the footer")
        #expect(report.spec.requirements.isEmpty)
        #expect(report.spec.exclusions.count == 1)
        #expect(report.dropped.contains { $0.contains("React") })
    }

    @Test func toleratesBulgarianInflection() {
        let spec = IntentSpec(objective: "Провери защо страницата зарежда бавно.", workflow: ["Анализирай зареждането на страницата."])
        let report = grounding.ground(spec, transcript: "искам да провериш защо страницата зарежда бавно")
        #expect(report.dropped.isEmpty)
    }

    @Test func crossLanguageOutputSkipsWordGrounding() {
        let spec = IntentSpec(objective: "Check why the page loads slowly.")
        #expect(grounding.ground(spec, transcript: "провери защо страницата зарежда бавно", checkWords: false).dropped.isEmpty)
    }
}

@Suite struct AnchorTests {
    @Test func extractsNumbersLatinTermsAndNames() {
        let anchors = PromptAnchors.extract(from: "Провери dashboard и API request-ите, бюджетът е 4500, пиши на Иван Петров")
        #expect(anchors.contains("dashboard"))
        #expect(anchors.contains("API"))
        #expect(anchors.contains("4500"))
    }

    @Test func destinationNamesAndPronounContractionsAreNotAnchors() {
        let anchors = PromptAnchors.extract(from: "I want Claude Code to check it, and I'm sure I'll finish, ask Maria")
        #expect(!anchors.contains("Claude"))
        #expect(!anchors.contains("Code"))
        #expect(!anchors.contains("I'm"))
        #expect(!anchors.contains("I'll"))
        #expect(anchors.contains("Maria"))
    }

    @Test func spokenNumberWordsAllowDigits() {
        #expect(PromptAnchors.inventedNumbers(in: "the first 3 clients", transcript: "the first three clients").isEmpty)
        #expect(PromptAnchors.inventedNumbers(in: "within 5 days", transcript: "soon") == ["5"])
    }
}

@Suite struct CoverageBackstopTests {
    @Test func appendsClausesTheModelDropped() {
        let missing = CoverageBackstop.missingClauses(
            transcript: "Rewrite my about section, make it friendly, and keep it under a hundred words.",
            prompt: "Rewrite my about section so it is friendly."
        )
        #expect(missing.contains { $0.lowercased().contains("hundred words") })
    }

    @Test func nothingMissingWhenEverythingIsCovered() {
        let missing = CoverageBackstop.missingClauses(
            transcript: "Rewrite my about section and make it friendly.",
            prompt: "Rewrite the about section. Make it friendly."
        )
        #expect(missing.isEmpty)
    }

    @Test func fillerOnlyClausesAreIgnored() {
        let missing = CoverageBackstop.missingClauses(
            transcript: "Okay so basically, I honestly just want a summary of the contract.",
            prompt: "Summarize the contract."
        )
        #expect(missing.isEmpty)
    }
}

@Suite struct PromptCompilerTests {
    private func compiler(_ provider: (any AIProvider)?) throws -> PromptCompiler {
        PromptCompiler(provider: provider, profiles: try store())
    }

    private let heroTranscript = "I want Claude Code to inspect my website because on mobile the hero isn't right, check how the section is built first, don't change desktop, and make sure nothing else breaks afterwards."

    private var goodSpec: IntentSpec {
        IntentSpec(
            objective: "Improve the mobile hero section of the website.", taskType: "coding",
            context: ["The hero is not right on mobile."], inputs: ["The website"],
            workflow: ["Check how the hero section is built first."],
            exclusions: ["Do not change the desktop layout."], validation: ["Make sure nothing else breaks afterwards."]
        )
    }

    @Test func buildsStructuredPromptFromExtractedIntent() async throws {
        let outcome = try await compiler(MockProvider.text(specJSON(goodSpec)).rawJSON())
            .compile(transcript: heroTranscript, profileID: "claude-code", preset: .structured)
        #expect(outcome.usedModel)
        #expect(outcome.notice == nil)
        #expect(outcome.prompt.contains("Improve the mobile hero section"))
        #expect(outcome.prompt.contains("Do not change the desktop layout."))
        #expect(outcome.prompt.contains("1. Inspect") || outcome.prompt.contains("Check how the hero section"))
    }

    @Test func providerFailureFallsBackWithoutLosingWords() async throws {
        let outcome = try await compiler(MockProvider.failing(.unavailable("Ollama is not running")))
            .compile(transcript: heroTranscript, profileID: "claude-code", preset: .structured)
        #expect(!outcome.usedModel)
        #expect(outcome.notice != nil)
        #expect(outcome.prompt.contains("hero"))
        #expect(outcome.prompt.contains("desktop"))
    }

    @Test func noProviderStillProducesAPrompt() async throws {
        let outcome = try await compiler(nil).compile(transcript: heroTranscript, profileID: "generic", preset: .quick)
        #expect(!outcome.usedModel)
        #expect(outcome.prompt.contains("hero"))
    }

    @Test func inventedNumbersAreRejectedThenFallBack() async throws {
        var bad = goodSpec
        bad.requirements = ["Make the CTA at least 48 pixels tall."]
        let outcome = try await compiler(MockProvider.text(specJSON(bad)).rawJSON())
            .compile(transcript: heroTranscript, profileID: "claude-code", preset: .structured)
        // 48 is not grounded in the speech, so the item is dropped by grounding and nothing invented survives.
        #expect(!outcome.prompt.contains("48"))
    }

    @Test func junkListItemsAreSanitized() async throws {
        var junky = goodSpec
        junky.workflow = ["],", "Check how the hero section is built first."]
        let outcome = try await compiler(MockProvider.text(specJSON(junky)).rawJSON())
            .compile(transcript: heroTranscript, profileID: "generic", preset: .structured)
        #expect(!outcome.prompt.contains("],"))
    }

    @Test func droppedSpokenDetailIsAppendedByBackstop() async throws {
        var thin = goodSpec
        thin.exclusions = []
        let outcome = try await compiler(MockProvider.text(specJSON(thin)).rawJSON())
            .compile(transcript: heroTranscript + " Keep the page loading fast.", profileID: "generic", preset: .structured)
        #expect(outcome.prompt.contains("Also mentioned"))
        #expect(outcome.prompt.lowercased().contains("loading fast"))
    }

    @Test func englishOutputFromBulgarianSpeechKeepsTechnicalTerms() async throws {
        let spec = IntentSpec(objective: "Check why the dashboard component makes too many API requests.", workflow: ["Inspect the dashboard component."])
        let outcome = try await compiler(MockProvider.text(specJSON(spec)).rawJSON())
            .compile(transcript: "Провери dashboard компонента и виж дали API request-ите са прекалено много",
                     profileID: "generic", preset: .structured, outputLanguage: .english)
        #expect(outcome.usedModel)
        #expect(outcome.prompt.contains("dashboard"))
        #expect(outcome.prompt.contains("API"))
    }

    @Test func transcriptIsSentAsJSONDataWithFixedSystemPrompt() async throws {
        let captured = Capture()
        let provider = MockProvider { messages in
            captured.set(messages)
            return specJSON(self.goodSpec)
        }
        _ = try await compiler(provider).compile(transcript: heroTranscript, profileID: "claude", preset: .structured)
        let messages = captured.messages
        #expect(messages.first?.content == IntentExtractor.systemPrompt)
        #expect(messages.last?.content.hasPrefix("{") == true)
    }

    @Test func systemPromptIsIdenticalAcrossProfilesForCaching() async throws {
        let first = Capture(), second = Capture()
        let a = MockProvider { first.set($0); return specJSON(self.goodSpec) }
        let b = MockProvider { second.set($0); return specJSON(self.goodSpec) }
        _ = try await compiler(a).compile(transcript: heroTranscript, profileID: "claude", preset: .structured)
        _ = try await compiler(b).compile(transcript: heroTranscript, profileID: "chatgpt", preset: .deep)
        #expect(first.messages.first?.content == second.messages.first?.content)
    }
}

private extension MockProvider {
    /// Mock whose reply is the raw JSON string (not wrapped in {"text": …}).
    func rawJSON() -> MockProvider { self.unwrapped() }

    func unwrapped() -> MockProvider {
        let inner = self
        return MockProvider { messages in
            let wrapped = try inner.reply(messages)
            guard let data = wrapped.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = object["text"] as? String else { return wrapped }
            return text
        }
    }
}

@Suite struct PromptFixtureEvaluationTests {
    private let fixture = PromptFixture(
        id: "t", category: "coding", profile: "generic", input: "fix the hero on mobile",
        mustPreserve: [["hero"], ["mobile", "phone"]], mustNotInvent: ["React", "px"], expectedSections: ["Validation"]
    )

    @Test func passesWhenConceptsPresentAndNothingInvented() {
        #expect(fixture.evaluate("Fix the hero on phones.\n\nValidation:\n- check").passed)
    }

    @Test func failsOnMissingConcept() {
        #expect(fixture.evaluate("Fix the layout.\n\nValidation:\n- check").missingConcepts == ["hero", "mobile"])
    }

    @Test func failsOnInventedTermButNotSubstrings() {
        #expect(fixture.evaluate("Fix the hero on mobile using React.\nValidation").invented == ["React"])
        #expect(fixture.evaluate("Fix the hero on mobile; keep expressions simple.\nValidation").invented.isEmpty)
    }

    @Test func termsTheSpeakerSaidAreNeverInvented() {
        var f = fixture
        f.input = "fix the hero on mobile with React"
        #expect(f.evaluate("Fix the hero on mobile with React.\nValidation").invented.isEmpty)
    }
}

@Suite struct SignalSkipTests {
    @Test func summarySignalIsSkippedWhenTheSpeakerAlreadyAskedForOne() throws {
        let store = try ProfileStore.load(userDirectory: nil)
        let spec = IntentSpec(objective: "Fix the bug.", workflow: ["Write a short summary of what changed."])
        let out = PromptRenderer().render(spec: spec, profile: store.profile("claude-code"), preset: .structured,
                                          presetConfig: store.preset(.structured), transcript: "fix the bug and write a summary", language: "en")
        #expect(!out.contains("Finish with a concise summary"))
        #expect(out.contains("Write a short summary of what changed."))
    }

    @Test func summarySignalStillFiresWhenNothingCoversIt() throws {
        let store = try ProfileStore.load(userDirectory: nil)
        let out = PromptRenderer().render(spec: IntentSpec(objective: "Fix the bug."), profile: store.profile("claude-code"), preset: .structured,
                                          presetConfig: store.preset(.structured), transcript: "fix the bug and report back what you found", language: "en")
        #expect(out.contains("Finish with a concise summary"))
    }
}

@Suite struct CoverageBackstopRegressionTests {
    private let transcript = "Make the new deck follow those principles but obviously don't copy the business info because it's different and research Citizens Club."

    @Test func aDroppedSubClauseInsideALongSentenceIsCaught() {
        let prompt = "Make the new deck follow those design principles.\n\n<context>\n- Citizens Club looks worse.\n</context>"
        let missing = CoverageBackstop.missingClauses(transcript: transcript, prompt: prompt)
        #expect(missing.contains { $0.lowercased().contains("copy the business info") })
    }

    @Test func sectionLabelsAndTagsDoNotCountAsSpokenWords() {
        // "research" appears only as a tag name here, so the spoken "research Citizens Club" is still missing.
        let prompt = "Improve the deck.\n\n<research>\n- Separate facts from assumptions.\n</research>\n\nContext:\n- The Citizens Club deck."
        let missing = CoverageBackstop.missingClauses(transcript: "Improve the deck and research Citizens Club pricing history.", prompt: prompt)
        #expect(missing.contains { $0.lowercased().contains("research") })
    }

    @Test func strippingKeepsRealContent() {
        let stripped = CoverageBackstop.stripScaffolding("<approach>\n1. Inspect the dashboard code.\n</approach>\n\nValidation:\n- Run the tests.")
        #expect(stripped.contains("Inspect the dashboard code"))
        #expect(stripped.contains("Run the tests"))
        #expect(!stripped.contains("approach"))
        #expect(!stripped.contains("Validation"))
    }
}
