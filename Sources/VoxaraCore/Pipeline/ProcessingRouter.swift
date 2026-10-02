import Foundation

/// The processor Voxara actually runs: vocabulary repair, then dictation cleanup or prompt compilation.
public struct ProcessingRouter: TextProcessor {
    public var refiner: DictationRefiner
    public var compiler: PromptCompiler
    public var repairer: TermRepairer?

    public init(refiner: DictationRefiner, compiler: PromptCompiler, repairer: TermRepairer?) {
        self.refiner = refiner
        self.compiler = compiler
        self.repairer = repairer
    }

    public func process(_ raw: String, context: ProcessingContext,
                        onStage: @escaping @Sendable (ProcessingStage) -> Void) async -> ProcessingResult {
        var text = raw
        if context.cleanup != .off || context.mode == .prompt, let repairer {
            text = await repairer.repair(raw).text
        }

        switch context.mode {
        case .dictation:
            var result = await refiner.process(text, context: context, onStage: onStage)
            if result.text.isEmpty { result.text = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            return result

        case .prompt:
            onStage(.buildingPrompt)
            let outcome = await compiler.compile(
                transcript: text, profileID: context.promptProfile, preset: context.promptPreset,
                outputLanguage: context.outputLanguage
            )
            return ProcessingResult(
                text: outcome.prompt, notice: outcome.notice,
                processor: outcome.usedModel ? "prompt-compiler" : "prompt-fallback"
            )
        }
    }
}
