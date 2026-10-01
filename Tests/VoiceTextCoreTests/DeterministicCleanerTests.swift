import Testing
@testable import VoiceTextCore

@Suite struct DeterministicCleanerTests {
    private let cleaner = DeterministicCleaner()

    @Test func removesHesitationSounds() {
        #expect(cleaner.clean("So um I think uh we should go") == "I think we should go")
    }

    @Test func removesBulgarianHesitations() {
        #expect(cleaner.clean("Искам ъъ да проверя ъм страницата") == "Искам да проверя страницата")
    }

    @Test func collapsesImmediateStutter() {
        #expect(cleaner.clean("I I think the the plan works") == "I think the plan works")
    }

    @Test func collapsesHyphenatedStutter() {
        #expect(cleaner.clean("We should wh-what do you think") == "We should what do you think")
    }

    @Test func keepsIntentionalRepetition() {
        // "very, very" has punctuation between the words, so it is deliberate emphasis.
        #expect(cleaner.clean("It was very, very good") == "It was very, very good")
    }

    @Test func doesNotCollapseLongRepeatedWords() {
        #expect(cleaner.clean("Send send me the report") == "Send me the report")
        #expect(cleaner.clean("They said that really really matters") == "They said that really really matters")
    }

    @Test func dropsLeadingDiscourseFiller() {
        #expect(cleaner.clean("okay so basically I need a summary") == "I need a summary")
    }

    @Test func keepsMidSentenceLike() {
        #expect(cleaner.clean("I would like to book a table") == "I would like to book a table")
    }

    @Test func capitalizesSentencesAndKeepsPunctuation() {
        #expect(cleaner.clean("first point. second point? third point") == "First point. Second point? Third point")
    }

    @Test func preservesEnglishTermsInsideBulgarian() {
        let input = "Провери dashboard компонента и виж дали API request-ите се изпълняват"
        let output = cleaner.clean(input)
        #expect(output.contains("dashboard"))
        #expect(output.contains("API"))
        #expect(output.contains("request-ите"))
    }

    @Test func doesNotChangeMeaningOfCleanText() {
        let input = "We should launch Tuesday and send the update to Maria."
        #expect(cleaner.clean(input) == input)
    }

    @Test func emptyInputStaysEmpty() {
        #expect(cleaner.clean("   ") == "")
        #expect(cleaner.clean("um uh") == "")
    }
}

@Suite struct SpokenCommandTests {
    private let cleaner = DeterministicCleaner()

    @Test func newLineAndParagraph() {
        #expect(cleaner.clean("first line new line second line") == "First line\nSecond line")
        #expect(cleaner.clean("intro new paragraph body") == "Intro\n\nBody")
    }

    @Test func punctuationWords() {
        #expect(cleaner.clean("hello comma world period") == "Hello, world.")
        #expect(cleaner.clean("note colon buy milk") == "Note: buy milk")
        #expect(cleaner.clean("really question mark") == "Really?")
    }

    @Test func doesNotDoublePunctuationAlreadyAdded() {
        #expect(cleaner.clean("Hello, comma world") == "Hello, world")
    }

    @Test func quotes() {
        #expect(cleaner.clean("he said open quote stop close quote") == "He said \u{201C}stop\u{201D}")
    }

    @Test func commandWordsInsideOtherWordsAreUntouched() {
        #expect(cleaner.clean("The periodic table has commas in it") == "The periodic table has commas in it")
    }

    @Test func bulgarianNewLineAndComma() {
        #expect(cleaner.clean("първо нов ред второ") == "Първо\nВторо")
        #expect(cleaner.clean("здравей запетая свят") == "Здравей, свят")
    }

    @Test func bulgarianPointNounIsNotPunctuation() {
        #expect(cleaner.clean("Това е точка на продажба") == "Това е точка на продажба")
    }
}

@Suite struct SelfCorrectionDetectorTests {
    @Test func detectsEnglishCorrections() {
        #expect(SelfCorrectionDetector.hasCorrection(in: "We should launch Friday, actually no, Tuesday"))
        #expect(SelfCorrectionDetector.hasCorrection(in: "Send it to John, scratch that, to Maria"))
    }

    @Test func detectsBulgarianCorrections() {
        #expect(SelfCorrectionDetector.hasCorrection(in: "Срещата е в петък, всъщност не, във вторник"))
    }

    @Test func plainSpeechIsNotACorrection() {
        #expect(!SelfCorrectionDetector.hasCorrection(in: "We should launch on Tuesday and send the update"))
    }
}

@Suite struct TextScriptTests {
    @Test func dominantScript() {
        #expect(TextScript.dominant(in: "Hello world") == .english)
        #expect(TextScript.dominant(in: "Здравей свят") == .bulgarian)
        #expect(TextScript.dominant(in: "Провери dashboard компонента") == .bulgarian)
        #expect(TextScript.dominant(in: "12345") == .none)
    }
}

@Suite struct TechTermPreservationTests {
    @Test func doesNotCapitalizeInsideDomainsAndFilenames() {
        let cleaner = DeterministicCleaner()
        #expect(cleaner.clean("use next.js with node.js") == "Use next.js with node.js")
        #expect(cleaner.clean("open package.json now") == "Open package.json now")
    }
}
