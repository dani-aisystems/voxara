import Foundation
import VoiceTextCore

// Phase 0 spike: transcribe WAV files with Parakeet.
// Usage: vt-bench stt <v3|ultra> <file.wav>...
let args = CommandLine.arguments.dropFirst()
guard args.first == "stt", args.count >= 3,
      let variant = ParakeetTranscriber.Variant(rawValue: args.dropFirst().first!)
else {
    print("usage: vt-bench stt <v3|ultra> <file.wav>...")
    exit(2)
}

let transcriber = ParakeetTranscriber(variant: variant)
let loadStart = Date()
try await transcriber.prepare { p in
    FileHandle.standardError.write("\rloading \(Int(p * 100))%".data(using: .utf8)!)
}
print("\nloaded \(variant.displayName) in \(String(format: "%.2f", Date().timeIntervalSince(loadStart)))s")

for path in args.dropFirst(2) {
    let samples = try AudioFileLoader.loadSamples(from: URL(fileURLWithPath: path))
    let result = try await transcriber.transcribe(samples: samples, language: .auto)
    print("[\(URL(fileURLWithPath: path).lastPathComponent)] \(String(format: "%.1fs audio, %.3fs stt", result.audioDuration, result.processingTime))")
    print("  \(result.text)")
}
