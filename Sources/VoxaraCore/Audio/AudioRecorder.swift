import AVFoundation
import Foundation
import os

public enum AudioRecorderError: LocalizedError, Equatable {
    case permissionDenied
    case noInputDevice
    case engineFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "Microphone access is not allowed. Enable Voxara in System Settings → Privacy & Security → Microphone."
        case .noInputDevice: "No microphone was found."
        case .engineFailed(let message): "Could not start the microphone: \(message)"
        }
    }
}

/// Captures microphone audio as 16 kHz mono Float32 using one long-lived converter per session.
public final class AudioRecorder: @unchecked Sendable {
    public typealias LevelHandler = @Sendable (Float) -> Void

    private let log = VoxaraLog.logger("audio")
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var isRecording = false
    /// Hard cap to protect memory if a key gets stuck (10 minutes).
    private let maxSamples = Int(AudioFormat.sampleRate * 600)
    public var onLevel: LevelHandler?

    public init() {}

    public static var permission: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    public static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func start() throws {
        guard Self.permission == .authorized else { throw AudioRecorderError.permissionDenied }
        if lock.withLock({ isRecording }) { return }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else { throw AudioRecorderError.noInputDevice }
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioFormat.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: target)
        else { throw AudioRecorderError.engineFailed("unsupported input format \(inputFormat)") }

        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            self.converter = converter
            isRecording = true
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer, target: target)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            lock.withLock { isRecording = false }
            throw AudioRecorderError.engineFailed(error.localizedDescription)
        }
    }

    /// Stops capture and returns all samples recorded since `start()`.
    @discardableResult
    public func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock {
            isRecording = false
            converter = nil
            let captured = samples
            samples.removeAll()
            return captured
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer, target: AVAudioFormat) {
        guard let converter = lock.withLock({ isRecording ? self.converter : nil }) else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        var supplied = false
        var error: NSError?
        // Feed exactly one buffer and report `.noDataNow` (not end-of-stream) so the
        // converter keeps its resampling state continuous across buffers.
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if let error {
            log.error("Audio conversion failed: \(error.localizedDescription)")
            return
        }
        guard let channel = output.floatChannelData?[0], output.frameLength > 0 else { return }
        let chunk = UnsafeBufferPointer(start: channel, count: Int(output.frameLength))

        var sum: Float = 0
        for value in chunk { sum += value * value }
        let rms = (sum / Float(chunk.count)).squareRoot()

        lock.withLock {
            if samples.count < maxSamples { samples.append(contentsOf: chunk) }
        }
        onLevel?(rms)
    }
}
