import Foundation
import Testing
@testable import VoxaraCore

private func tempFile(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("vx-\(UUID().uuidString)-\(name)")
}

@Suite struct SettingsTests {
    @Test func defaultsMatchTheProductBrief() {
        let s = AppSettings()
        #expect(s.dictationShortcut == .modifier(.rightOption))
        #expect(s.promptShortcut == .modifier(.rightCommand))
        #expect(s.cleanup == .smart)
        #expect(s.promptPreset == .structured)
        #expect(!s.testMode)
        #expect(s.saveHistory)
    }

    @Test func roundTripsThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: "vx-test-\(UUID().uuidString)")!
        var s = AppSettings()
        s.cleanup = .thorough
        s.promptProfile = "claude-code"
        s.promptShortcut = .combo(keyCode: 49, modifiers: [.leftControl, .leftOption])
        SettingsPersistence.save(s, to: defaults)
        #expect(SettingsPersistence.load(from: defaults) == s)
    }

    @Test func missingKeysFallBackToDefaultsInsteadOfResettingEverything() throws {
        let json = #"{"cleanup":"light","promptProfile":"claude"}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(s.cleanup == .light)
        #expect(s.promptProfile == "claude")
        #expect(s.dictationShortcut == .defaultDictation)
    }

    @Test func corruptSettingsLoadAsDefaults() {
        let defaults = UserDefaults(suiteName: "vx-test-\(UUID().uuidString)")!
        defaults.set(Data("not json".utf8), forKey: SettingsPersistence.key)
        #expect(SettingsPersistence.load(from: defaults) == AppSettings())
    }

    @Test func shortcutValidation() {
        #expect(ShortcutValidation.conflict(dictation: .defaultDictation, prompt: .defaultDictation) != nil)
        #expect(ShortcutValidation.conflict(dictation: .defaultDictation, prompt: .defaultPrompt) == nil)
        #expect(ShortcutValidation.warning(for: .modifier(.function)) != nil)
        #expect(ShortcutValidation.warning(for: .modifier(.leftCommand)) != nil)
        #expect(ShortcutValidation.warning(for: .modifier(.rightOption)) == nil)
    }
}

@MainActor
@Suite struct HistoryTests {
    private func record(_ text: String, mode: HotkeyAction = .dictation, app: String = "TextEdit", secondsAgo: TimeInterval = 0,
                        stt: TimeInterval = 0.2, processing: TimeInterval = 0.0, processor: String = "rules") -> DictationRecord {
        var t = PipelineTimings()
        let start = Date().addingTimeInterval(-secondsAgo)
        t.recordingStarted = start
        t.recordingEnded = start.addingTimeInterval(4)
        t.sttStarted = start.addingTimeInterval(4)
        t.sttCompleted = start.addingTimeInterval(4 + stt)
        t.processingStarted = start.addingTimeInterval(4 + stt)
        t.processingCompleted = start.addingTimeInterval(4 + stt + processing)
        t.injected = start.addingTimeInterval(4 + stt + processing + 0.1)
        return DictationRecord(date: start, mode: mode, rawTranscript: "raw " + text, finalText: text, targetApp: app,
                               targetBundleID: "x.\(app)", processor: processor, inserted: true, timings: t)
    }

    @Test func addsNewestFirstAndPersists() {
        let url = tempFile("history.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HistoryStore(fileURL: url)
        store.add(record("first"))
        store.add(record("second"))
        #expect(store.entries.map(\.finalText) == ["second", "first"])
        #expect(HistoryStore(fileURL: url).entries.map(\.finalText) == ["second", "first"])
    }

    @Test func enforcesLimit() {
        let store = HistoryStore(fileURL: tempFile("h.json"), limit: 3)
        for i in 0..<5 { store.add(record("item \(i)")) }
        #expect(store.entries.count == 3)
        #expect(store.entries.first?.finalText == "item 4")
    }

    @Test func searchMatchesFinalRawAndAppAndFiltersMode() {
        let store = HistoryStore(fileURL: tempFile("h.json"))
        store.add(record("Send the invoice", app: "Mail"))
        store.add(record("Investigate the dashboard", mode: .prompt, app: "Terminal"))
        #expect(store.search("invoice").count == 1)
        #expect(store.search("RAW investigate").count == 1)
        #expect(store.search("terminal").count == 1)
        #expect(store.search("", mode: .prompt).count == 1)
        #expect(store.search("nothing").isEmpty)
    }

    @Test func deleteAndClear() {
        let store = HistoryStore(fileURL: tempFile("h.json"))
        let a = record("a")
        store.add(a)
        store.add(record("b"))
        store.delete(a.id)
        #expect(store.entries.map(\.finalText) == ["b"])
        store.clear()
        #expect(store.entries.isEmpty)
    }

    @Test func historyNeverStoresAudioFields() throws {
        let data = try JSONEncoder().encode(record("x"))
        let text = String(data: data, encoding: .utf8)!.lowercased()
        #expect(!text.contains("audio\":"))
        #expect(!text.contains("samples"))
    }

    @Test func statsAreComputedOnlyFromRealTimings() {
        let records = [
            record("a", stt: 0.2), record("b", stt: 0.4), record("c", stt: 0.6),
            record("p", mode: .prompt, stt: 0.3, processing: 4.0, processor: "prompt-compiler"),
            record("m", stt: 0.2, processing: 1.2, processor: "ollama"),
        ]
        let s = UsageStats.compute(records)
        #expect(s.count == 5)
        #expect(s.dictations == 4)
        #expect(s.prompts == 1)
        #expect(abs(s.secondsSpoken - 20) < 0.01)
        #expect(abs((s.medianSTT ?? 0) - 0.3) < 0.001)
        #expect(abs((s.medianPrompt ?? 0) - 4.0) < 0.001)
        // Rule-only cleanup is excluded so it cannot hide model latency.
        #expect(abs((s.medianCleanup ?? 0) - 1.2) < 0.001)
    }

    @Test func emptyHistoryHasNoFakeNumbers() {
        let s = UsageStats.compute([])
        #expect(s.count == 0)
        #expect(s.medianSTT == nil)
        #expect(s.medianTotal == nil)
    }

    @Test func todayFiltersByCalendarDay() {
        let calendar = Calendar.current
        let old = record("old", secondsAgo: 3 * 86_400)
        let today = record("today")
        #expect(UsageStats.today([old, today], calendar: calendar).count == 1)
    }
}

@Suite struct AppContextTests {
    private func resolve(_ action: HotkeyAction = .prompt, bundle: String?, title: String? = nil, settings: AppSettings = AppSettings(),
                         pref: AppPreference? = nil) -> ResolvedContext {
        ResolvedContext.resolve(action: action, bundleID: bundle, windowTitle: title, settings: settings, preference: pref)
    }

    @Test func terminalAndEditorsSuggestClaudeCode() {
        for id in ["com.apple.Terminal", "com.microsoft.VSCode", "com.google.antigravity-ide", "com.jetbrains.pycharm"] {
            #expect(resolve(bundle: id).promptProfile == "claude-code", "\(id)")
        }
    }

    @Test func aiChatAppsSuggestTheirOwnProfile() {
        #expect(resolve(bundle: "com.openai.codex").promptProfile == "chatgpt")
        #expect(resolve(bundle: "com.anthropic.claudefordesktop").promptProfile == "claude")
    }

    @Test func browsersOnlyInferFromAUnambiguousPageTitle() {
        #expect(resolve(bundle: "com.brave.Browser", title: "ChatGPT").promptProfile == "chatgpt")
        #expect(resolve(bundle: "com.brave.Browser", title: "Claude").promptProfile == "claude")
        #expect(resolve(bundle: "com.brave.Browser", title: "Some random page").promptProfile == "generic")
    }

    @Test func unknownAppUsesGlobalDefaults() {
        var s = AppSettings()
        s.promptProfile = "chatgpt"
        let r = resolve(bundle: "com.example.unknown", settings: s)
        #expect(r.promptProfile == "chatgpt")
        #expect(r.source == "Default")
    }

    @Test func contextAwarenessCanBeSwitchedOff() {
        var s = AppSettings()
        s.contextAware = false
        #expect(resolve(bundle: "com.apple.Terminal", settings: s).promptProfile == "generic")
    }

    @Test func suggestionsMayOnlyLightenCleanup() {
        var s = AppSettings()
        s.cleanup = .smart
        #expect(resolve(.dictation, bundle: "com.apple.MobileSMS", settings: s).cleanup == .light)
        s.cleanup = .off
        #expect(resolve(.dictation, bundle: "com.apple.MobileSMS", settings: s).cleanup == .off)
    }

    @Test func explicitAppSettingsAlwaysWin() {
        let pref = AppPreference(bundleID: "com.apple.Terminal", displayName: "Terminal", promptProfile: "claude", cleanup: .thorough)
        let r = resolve(bundle: "com.apple.Terminal", pref: pref)
        #expect(r.promptProfile == "claude")
        #expect(r.cleanup == .thorough)
        #expect(r.source == "App setting")
    }

    @Test func hotkeyDecidesTheModeUnlessTheAppOptedIn() {
        #expect(resolve(.dictation, bundle: "com.apple.Terminal").mode == .dictation)
        #expect(resolve(.prompt, bundle: "com.apple.MobileSMS").mode == .prompt)
        let pref = AppPreference(bundleID: "com.apple.Terminal", displayName: "Terminal", dictationKeyProducesPrompt: true)
        #expect(resolve(.dictation, bundle: "com.apple.Terminal", pref: pref).mode == .prompt)
    }
}

@MainActor
@Suite struct AppPreferencesStoreTests {
    @Test func remembersAppsAndPersistsOverrides() {
        let url = tempFile("apps.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppPreferencesStore(fileURL: url)
        store.noteUsage(bundleID: "com.apple.Terminal", name: "Terminal")
        var pref = store.preference(for: "com.apple.Terminal")!
        pref.promptProfile = "claude-code"
        store.update(pref)
        let reloaded = AppPreferencesStore(fileURL: url)
        #expect(reloaded.preference(for: "com.apple.Terminal")?.promptProfile == "claude-code")
        #expect(reloaded.sorted.count == 1)
    }

    @Test func ignoresNilBundle() {
        let store = AppPreferencesStore(fileURL: tempFile("apps.json"))
        store.noteUsage(bundleID: nil, name: "x")
        #expect(store.sorted.isEmpty)
    }
}

@Suite struct ProcessingRouterTests {
    private func router(provider: (any AIProvider)?, vocab: [VocabularyEntry] = VocabularyStore.seed) throws -> ProcessingRouter {
        ProcessingRouter(
            refiner: DictationRefiner(provider: provider),
            compiler: PromptCompiler(provider: provider, profiles: try ProfileStore.load(userDirectory: nil)),
            repairer: TermRepairer(entries: vocab, lexicon: FakeLexicon())
        )
    }

    @Test func dictationModeCleansAndRepairsVocabulary() async throws {
        let ctx = ProcessingContext(mode: .dictation, language: .auto, cleanup: .light)
        let result = try await router(provider: nil).process("um провери дешбод компонента", context: ctx) { _ in }
        #expect(result.text == "Провери dashboard компонента")
        #expect(result.processor == "rules")
    }

    @Test func cleanupOffLeavesTextUntouched() async throws {
        let ctx = ProcessingContext(mode: .dictation, language: .auto, cleanup: .off)
        let result = try await router(provider: nil).process("um hello", context: ctx) { _ in }
        #expect(result.text == "um hello")
    }

    @Test func promptModeBuildsAPromptAndReportsStage() async throws {
        let spec = IntentSpec(objective: "Review the pricing page.", requirements: ["Check the pricing page copy."])
        let data = try JSONEncoder().encode(spec)
        let provider = MockProvider { _ in String(data: data, encoding: .utf8)! }
        let stages = Capture2()
        let ctx = ProcessingContext(mode: .prompt, language: .auto, promptProfile: "generic", promptPreset: .structured)
        let result = try await router(provider: provider).process("review the pricing page and check the copy", context: ctx) { stages.add($0) }
        #expect(result.processor == "prompt-compiler")
        #expect(result.text.contains("Review the pricing page."))
        #expect(stages.values.contains(.buildingPrompt))
    }

    @Test func promptModeDegradesToABasicPromptWhenModelIsDown() async throws {
        let ctx = ProcessingContext(mode: .prompt, language: .auto, promptProfile: "claude-code")
        let result = try await router(provider: MockProvider.failing(.unavailable("down")))
            .process("check why the dashboard is slow and run the tests", context: ctx) { _ in }
        #expect(result.processor == "prompt-fallback")
        #expect(result.notice != nil)
        #expect(result.text.contains("dashboard"))
    }
}

final class Capture2: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ProcessingStage] = []
    var values: [ProcessingStage] { lock.withLock { stored } }
    func add(_ value: ProcessingStage) { lock.withLock { stored.append(value) } }
}
