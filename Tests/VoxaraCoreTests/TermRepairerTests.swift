import Testing
@testable import VoxaraCore

/// Deterministic stand-in for the macOS Bulgarian dictionary.
struct FakeLexicon: BulgarianLexicon {
    var known: Set<String> = [
        "провери", "компонента", "компонент", "сървър", "сървъра", "страницата", "зарежда", "виж", "дали",
        "се", "изпълняват", "много", "пъти", "на", "и", "в", "файл", "тестовете", "направи", "новата", "версия",
        "след", "като", "пусни", "ми", "прати", "линк", "към", "облак", "искам", "да", "код", "реда",
    ]
    var available = true

    func isKnownWord(_ word: String) async -> Bool? {
        available ? known.contains(word.lowercased()) : nil
    }
}

@Suite struct TermRepairerTests {
    private let repairer = TermRepairer(entries: VocabularyStore.seed, lexicon: FakeLexicon())

    @Test func restoresObservedParakeetTransliterations() async {
        let (text, _) = await repairer.repair("Провери дешбод компонента и виж дали епи заявките са много.")
        #expect(text == "Провери dashboard компонента и виж дали API заявките са много.")
    }

    @Test func keepsGenuineBulgarianLoanwords() async {
        let (text, replacements) = await repairer.repair("Провери компонента и сървъра, после файл.")
        #expect(text == "Провери компонента и сървъра, после файл.")
        #expect(replacements.isEmpty)
    }

    @Test func keepsBulgarianSuffixWithHyphen() async {
        let (text, _) = await repairer.repair("Пусни деплоя и после бекенда.")
        #expect(text.contains("deploy"))
        #expect(!text.contains("деплой"))
        #expect(text.contains("backend-а"))
    }

    @Test func phoneticMatchForUnlistedSpelling() async {
        // "дашборд" is not an alias; it is restored phonetically because the dictionary does not know it.
        let (text, _) = await repairer.repair("Отвори дашборда на проекта.")
        #expect(text.contains("dashboard-а"))
    }

    @Test func phoneticMatchRequiresUnknownWord() async {
        // If the dictionary vouches for the word, it stays Bulgarian even when it sounds like a term.
        var lexicon = FakeLexicon()
        lexicon.known.insert("реакт")
        let strict = TermRepairer(entries: [VocabularyEntry(term: "React")], lexicon: lexicon)
        let (text, _) = await strict.repair("Направи реакт на промяната.")
        #expect(text == "Направи реакт на промяната.")
    }

    @Test func noPhoneticRepairWhenLexiconUnavailable() async {
        let offline = TermRepairer(entries: [VocabularyEntry(term: "dashboard")], lexicon: FakeLexicon(available: false))
        let (text, _) = await offline.repair("Отвори дашборда.")
        #expect(text == "Отвори дашборда.")
    }

    @Test func multiWordAliasesInEnglish() async {
        let (text, _) = await repairer.repair("Open the cloud code terminal and ask chat gpt.")
        #expect(text == "Open the Claude Code terminal and ask ChatGPT.")
    }

    @Test func englishWordsAreNotPhoneticallyRewritten() async {
        let (text, _) = await repairer.repair("The cloud is fast and the board looks good.")
        #expect(text == "The cloud is fast and the board looks good.")
    }

    @Test func cloudSlangInBulgarianIsNotClaude() async {
        let (text, _) = await repairer.repair("Искам клауд инфраструктура за проекта.")
        #expect(!text.contains("Claude"))
    }

    @Test func gitHubAndPullRequestFromObservedOutput() async {
        let (text, _) = await repairer.repair("Прати линк към полреквеста в бжитхаб.")
        #expect(text == "Прати линк към pull request-а в GitHub.")
    }

    @Test func disabledEntriesAreIgnored() async {
        var entry = VocabularyEntry(term: "dashboard", aliases: ["дешбод"])
        entry.enabled = false
        let (text, _) = await TermRepairer(entries: [entry], lexicon: FakeLexicon()).repair("Провери дешбод.")
        #expect(text == "Провери дешбод.")
    }

    @Test func phoneticKeys() {
        #expect(Phonetic.key(Phonetic.transliterate("дешбод")) == Phonetic.key("dashboard"))
        #expect(Phonetic.key(Phonetic.transliterate("фронтенд")) == Phonetic.key("frontend"))
        #expect(Phonetic.key(Phonetic.transliterate("пайтън")) == Phonetic.key("python"))
        #expect(Phonetic.key(Phonetic.transliterate("ноушън")) == Phonetic.key("notion"))
        #expect(Phonetic.key(Phonetic.transliterate("сървър")) == Phonetic.key("server"))
    }
}
