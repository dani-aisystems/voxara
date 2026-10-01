import Foundation

/// Detects explicit spoken self-corrections ("Friday — actually no, Tuesday"). Resolving them
/// needs understanding, so the detector only decides *whether* the language model should run.
public enum SelfCorrectionDetector {
    private static let english = [
        "actually no", "actually, no", "no wait", "no, wait", "wait no", "wait, no", "scratch that",
        "i mean", "or rather", "sorry,", "let me rephrase", "correction", "no no", "not that",
        "never mind", "nevermind", "make that", "i meant", "or actually", "actually,",
    ]

    private static let bulgarian = [
        "всъщност не", "не, чакай", "чакай,", "не чакай", "по-точно", "искам да кажа", "извинявай",
        "зачеркни", "забрави", "не, а", "не а", "исках да кажа", "по-скоро", "всъщност,",
    ]

    public static func hasCorrection(in text: String) -> Bool {
        let lower = text.lowercased()
        return (english + bulgarian).contains { lower.contains($0) }
    }
}
