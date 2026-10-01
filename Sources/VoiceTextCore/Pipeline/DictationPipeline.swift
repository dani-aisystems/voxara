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
    case done(InsertionOutcome, notice: String?)
    case failed(message: String, recoverableText: String?)
}

/// One finished dictation, handed to history and the "last result" menu item.
public struct DictationRecord: Codable, Sendable, Identifiable, Equatable {
    public var id = UUID()
    public var date: Date
    public var mode: HotkeyAction
    public var language: SpeechLanguage
    public var rawTranscript: String
    public var finalText: String
    public var targetApp: String?
    public var targetBundleID: String?
    public var processor: String
    public var inserted: Bool
    public var timings: PipelineTimings

    public init(date: Date, mode: HotkeyAction, language: SpeechLanguage, rawTranscript: String, finalText: String,
                targetApp: String?, targetBundleID: String?, processor: String, inserted: Bool, timings: PipelineTimings) {
        self.date = date
        self.mode = mode
        self.language = language
        self.rawTranscript = rawTranscript
        self.finalText = finalText
        self.targetApp = targetApp
        self.targetBundleID = targetBundleID
        self.processor = processor
        self.inserted = inserted
        self.timings = timings
    }
}

/// Orchestrates hotkey → record → transcribe → process → insert.
@MainActor
public final class DictationPipeline {
    private let log = Logger(subsystem: "com.daniel.voicetext", category: "pipeline")
    private let recorder: AudioRecorder
    private let transcriber: any SpeechTranscriber
    private let injector: TextInjector
    public var processor: any TextProcessor
    public var language: SpeechLanguage = .auto

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

    /// Runs the full pipeline on pre-recorded audio (debug/E2E testing), inserting into the frontmost app.
    public func runFile(_ url: URL, action: HotkeyAction) {
        guard !isBusy else { return }
        do {
            let samples = try AudioFileLoader.loadSamples(from: url)
            target = FocusCapture.current()
            timings = PipelineTimings()
            timings.recordingStarted = Date().addingTimeInterval(-Double(samples.count) / AudioFormat.sampleRate)
            timings.recordingEnded = Date()
            timings.audioPrepared = Date()
            run(samples: samples, action: action)
        } catch {
            state = .failed(message: "Could not read audio file: \(error.localizedDescription)", recoverableText: nil)
        }
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
        work = Task { [weak self] in
            guard let self else { return }
            self.state = .transcribing(action)
            self.timings.sttStarted = Date()
            let raw: String
            do {
                raw = try await self.transcriber.transcribe(samples: samples, language: language).text
            } catch {
                self.log.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                self.state = .failed(message: error.localizedDescription, recoverableText: nil)
                return
            }
            self.timings.sttCompleted = Date()
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.state = .failed(message: "No speech detected.", recoverableText: nil)
                return
            }

            let context = ProcessingContext(mode: action, language: language, targetBundleID: target?.bundleID, targetAppName: target?.appName)
            self.timings.processingStarted = Date()
            let result = await self.processor.process(raw, context: context) { stage in
                Task { @MainActor in self.showStage(stage, for: action) }
            }
            self.timings.processingCompleted = Date()
            self.lastResult = result.text

            let outcome = await self.injector.insert(result.text, into: target)
            self.timings.injected = Date()
            self.log.info("Dictation finished: \(self.timings.summary, privacy: .public)")

            var inserted = false
            if case .inserted = outcome { inserted = true }
            self.onRecord?(DictationRecord(
                date: Date(), mode: action, language: language, rawTranscript: raw, finalText: result.text,
                targetApp: target?.appName, targetBundleID: target?.bundleID, processor: result.processor,
                inserted: inserted, timings: self.timings
            ))
            if case .copiedToClipboard(let reason) = outcome {
                self.state = .failed(message: "\(reason). Text copied — press ⌘V.", recoverableText: result.text)
            } else {
                self.state = .done(outcome, notice: result.notice)
            }
        }
    }
}
