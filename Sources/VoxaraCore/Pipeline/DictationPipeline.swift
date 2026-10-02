import AppKit
import Foundation
import os

/// What the overlay and menu should show.
public enum PipelineState: Sendable, Equatable {
    case idle
    case listening(HotkeyAction, startedAt: Date)
    case transcribing(HotkeyAction)
    case processing(HotkeyAction, ProcessingStage)
    /// `notice` reports degraded-but-successful processing (e.g. AI unavailable, basic cleanup used).
    case done(HotkeyAction, InsertionOutcome, notice: String?)
    /// `recoverableText` is the generated text when it could not be inserted; it is never discarded.
    case failed(message: String, recoverableText: String?)
}

/// Orchestrates hotkey → record → transcribe → process → insert.
@MainActor
public final class DictationPipeline {
    private let log = VoxaraLog.logger("pipeline")
    private let recorder: AudioRecorder
    private let transcriber: any SpeechTranscriber
    private let injector: TextInjector
    public var processor: any TextProcessor
    public var language: SpeechLanguage = .auto
    public var outputLanguage: PromptOutputLanguage = .sameAsSpeech

    /// Decides profile, preset, cleanup and the effective mode for the focused app.
    public var contextResolver: ((HotkeyAction, InsertionTarget?) -> ResolvedContext)?
    /// Returns a reason to *not* insert into this target (e.g. test mode), or nil to allow.
    public var insertionGuard: ((InsertionTarget?) -> String?)?

    public var onStateChange: ((PipelineState) -> Void)?
    public var onLevel: ((Float) -> Void)?
    public var onRecord: ((DictationRecord) -> Void)?

    public private(set) var state: PipelineState = .idle {
        didSet { onStateChange?(state) }
    }
    public private(set) var lastResult: String?

    private var target: InsertionTarget?
    private var timings = PipelineTimings()
    private var activeAction: HotkeyAction?
    private var work: Task<Void, Never>?

    /// Recordings shorter than this are treated as accidental.
    private let minimumAudio: TimeInterval = 0.3

    public init(recorder: AudioRecorder, transcriber: any SpeechTranscriber, injector: TextInjector, processor: any TextProcessor) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.injector = injector
        self.processor = processor
        recorder.onLevel = { [weak self] level in
            Task { @MainActor in self?.onLevel?(level) }
        }
    }

    public var isBusy: Bool {
        switch state {
        case .listening, .transcribing, .processing: true
        default: false
        }
    }

    public func handle(_ signal: HotkeySignal) {
        switch signal {
        case .start(let action): start(action)
        case .stop(let action): finish(action)
        case .cancel(let action): cancel(action)
        }
    }

    public func start(_ action: HotkeyAction) {
        guard !isBusy else { return }
        work?.cancel()
        target = FocusCapture.current()
        timings = PipelineTimings()
        timings.recordingStarted = Date()
        do {
            try recorder.start()
            activeAction = action
            state = .listening(action, startedAt: Date())
        } catch {
            log.error("Recorder failed to start: \(error.localizedDescription, privacy: .public)")
            state = .failed(message: error.localizedDescription, recoverableText: nil)
        }
    }

    public func cancel(_ action: HotkeyAction) {
        guard activeAction == action, case .listening = state else { return }
        recorder.stop()
        activeAction = nil
        state = .idle
    }

    public func finish(_ action: HotkeyAction) {
        guard activeAction == action, case .listening = state else { return }
        let samples = recorder.stop()
        activeAction = nil
        timings.recordingEnded = Date()
        let duration = Double(samples.count) / AudioFormat.sampleRate
        guard duration >= minimumAudio else {
            state = .idle
            return
        }
        timings.audioPrepared = Date()
        run(samples: samples, action: action)
    }

    /// Runs the pipeline on pre-recorded audio (testing). Insertion only happens when the frontmost app
    /// is exactly `expectBundleID`, so a test can never type into whatever the user is working in.
    public func runFile(_ url: URL, action: HotkeyAction, expectBundleID: String) {
        guard !isBusy else { return }
        let front = FocusCapture.current()
        guard front?.bundleID == expectBundleID else {
            log.warning("Test run refused: frontmost is \(front?.bundleID ?? "nil", privacy: .public), expected \(expectBundleID, privacy: .public)")
            state = .failed(message: "Test run refused: \(front?.appName ?? "unknown app") is frontmost, expected \(expectBundleID).",
                            recoverableText: nil)
            return
        }
        do {
            let samples = try AudioFileLoader.loadSamples(from: url)
            target = front
            timings = PipelineTimings()
            timings.recordingStarted = Date().addingTimeInterval(-Double(samples.count) / AudioFormat.sampleRate)
            timings.recordingEnded = Date()
            timings.audioPrepared = Date()
            run(samples: samples, action: action)
        } catch {
            state = .failed(message: "Could not read audio file: \(error.localizedDescription)", recoverableText: nil)
        }
    }

    /// Processes typed text through the same mode logic without recording or inserting (Command Center "Try it").
    public func preview(_ text: String, action: HotkeyAction, context: ResolvedContext) async -> ProcessingResult {
        let processingContext = ProcessingContext(
            mode: context.mode, language: language, promptProfile: context.promptProfile,
            promptPreset: context.promptPreset, cleanup: context.cleanup, outputLanguage: outputLanguage
        )
        return await processor.process(text, context: processingContext) { _ in }
    }

    /// Stage updates arrive asynchronously; never let a late one overwrite the final state.
    private func showStage(_ stage: ProcessingStage, for action: HotkeyAction) {
        switch state {
        case .transcribing(action), .processing(action, _): state = .processing(action, stage)
        default: break
        }
    }

    private func run(samples: [Float], action: HotkeyAction) {
        let language = language
        let target = target
        let resolved = contextResolver?(action, target)
            ?? ResolvedContext(mode: action, promptProfile: "generic", promptPreset: .structured, cleanup: .smart, source: "Default")
        let mode = resolved.mode
        let context = ProcessingContext(
            mode: mode, language: language, targetBundleID: target?.bundleID, targetAppName: target?.appName,
            promptProfile: resolved.promptProfile, promptPreset: resolved.promptPreset, cleanup: resolved.cleanup,
            outputLanguage: outputLanguage
        )

        work = Task { [self] in
            state = .transcribing(mode)
            timings.sttStarted = Date()
            let raw: String
            do {
                raw = try await transcriber.transcribe(samples: samples, language: language).text
            } catch {
                log.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(message: error.localizedDescription, recoverableText: nil)
                return
            }
            timings.sttCompleted = Date()
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state = .failed(message: "No speech detected.", recoverableText: nil)
                return
            }

            timings.processingStarted = Date()
            let result = await processor.process(raw, context: context) { stage in
                Task { @MainActor in self.showStage(stage, for: mode) }
            }
            timings.processingCompleted = Date()
            guard !result.text.isEmpty else {
                state = .failed(message: "Nothing to insert after cleanup.", recoverableText: raw)
                return
            }
            lastResult = result.text

            let outcome: InsertionOutcome
            if let reason = insertionGuard?(target) {
                outcome = .copiedToClipboard(reason: reason)
            } else {
                outcome = await injector.insert(result.text, into: target)
            }
            timings.injected = Date()
            log.info("\(mode.rawValue, privacy: .public) finished: \(self.timings.summary, privacy: .public)")

            var inserted = false
            if case .inserted = outcome { inserted = true }
            onRecord?(DictationRecord(
                date: Date(), mode: mode, rawTranscript: raw, finalText: result.text,
                targetApp: target?.appName, targetBundleID: target?.bundleID, processor: result.processor,
                promptProfile: mode == .prompt ? resolved.promptProfile : nil,
                promptPreset: mode == .prompt ? resolved.promptPreset : nil,
                cleanup: mode == .dictation ? resolved.cleanup : nil,
                inserted: inserted, notice: result.notice, timings: timings
            ))
            if case .copiedToClipboard(let reason) = outcome {
                state = .failed(message: reason, recoverableText: result.text)
            } else {
                state = .done(mode, outcome, notice: result.notice)
            }
        }
    }
}
