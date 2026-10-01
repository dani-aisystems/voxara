import Foundation
import VoxaraCore

// vx-bench: development benchmarks.
//   vx-bench stt <v3|ultra> <file.wav>...         transcribe files with Parakeet
//   vx-bench refine <ollama-model> [fixtures.json] run dictation fixtures through the refiner

let args = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("usage: vx-bench stt <v3|ultra> <file.wav>...\n       vx-bench refine <ollama-model> [fixtures.json]")
    exit(2)
}

guard let command = args.first else { usage() }

switch command {
case "stt":
    guard args.count >= 3, let variant = ParakeetTranscriber.Variant(rawValue: args[1]) else { usage() }
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

case "refine":
    guard args.count >= 2 else { usage() }
    let provider = OllamaProvider(model: args[1])
    let path = args.count > 2 ? args[2] : "Tests/VoxaraCoreTests/Fixtures/dictation/dictation.json"
    let fixtures = try DictationFixture.load(from: URL(fileURLWithPath: path))
    guard await provider.isAvailable() else {
        print("Model \(args[1]) is not available in Ollama (is it pulled and is the service running?)")
        exit(1)
    }
    await provider.warmUp()
    let refiner = DictationRefiner(provider: provider, mode: .always, timeout: 20)
    let context = ProcessingContext(mode: .dictation, language: .auto)
    var passed = 0
    var total: TimeInterval = 0
    for fixture in fixtures {
        let start = Date()
        let result = await refiner.process(fixture.input, context: context) { _ in }
        let elapsed = Date().timeIntervalSince(start)
        total += elapsed
        let eval = fixture.evaluate(result.text)
        if eval.passed { passed += 1 }
        print("\(eval.passed ? "PASS" : "FAIL") \(fixture.id) [\(result.processor)] \(String(format: "%.2fs", elapsed))")
        print("   in:  \(fixture.input)")
        print("   out: \(result.text.replacingOccurrences(of: "\n", with: "⏎"))")
        if !eval.missing.isEmpty { print("   missing: \(eval.missing)") }
        if !eval.forbidden.isEmpty { print("   forbidden: \(eval.forbidden)") }
    }
    print("\n\(passed)/\(fixtures.count) passed, avg \(String(format: "%.2fs", total / Double(fixtures.count))) per item, model \(args[1])")

default:
    usage()
}
