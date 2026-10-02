import Foundation
import VoxaraCore

// vx-bench: development benchmarks.
//   vx-bench stt <v3|ultra> <file.wav>...         transcribe files with Parakeet
//   vx-bench refine <ollama-model> [fixtures.json] run dictation fixtures through the refiner
//   vx-bench prompt <ollama-model> [preset] [profile-override]  run Prompt Mode fixtures

let args = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("usage: vx-bench stt <v3|ultra> <file.wav>...\n       vx-bench refine <ollama-model> [fixtures.json]\n       vx-bench prompt <ollama-model> [quick|structured|deep] [profile]")
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
    let refiner = DictationRefiner(provider: provider, timeout: 20)
    let context = ProcessingContext(mode: .dictation, language: .auto, cleanup: .thorough)
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

case "prompt":
    let positional = args.filter { !$0.hasPrefix("--") }
    guard positional.count >= 2 else { usage() }
    let provider = OllamaProvider(model: positional[1])
    let preset = positional.count > 2 ? (PromptPreset(rawValue: positional[2]) ?? .structured) : .structured
    let profileOverride = positional.count > 3 ? positional[3] : nil
    let only = args.first { $0.hasPrefix("--only=") }.map { String($0.dropFirst(7)) }
    let fixtures = try PromptFixture.load(from: URL(fileURLWithPath: "Tests/VoxaraCoreTests/Fixtures/prompt/prompt-fixtures.json"))
        .filter { only == nil || $0.id.contains(only!) }
    guard await provider.isAvailable() else {
        print("Model \(positional[1]) is not available in Ollama")
        exit(1)
    }
    await provider.warmUp()
    let compiler = PromptCompiler(provider: provider, profiles: try ProfileStore.load(userDirectory: nil))
    var passed = 0
    var total: TimeInterval = 0
    var modelUsed = 0
    for fixture in fixtures {
        let profile = profileOverride ?? fixture.profile
        let start = Date()
        let outcome = await compiler.compile(transcript: fixture.input, profileID: profile, preset: preset)
        let elapsed = Date().timeIntervalSince(start)
        total += elapsed
        if outcome.usedModel { modelUsed += 1 }
        // Quick output has no section labels by design, so section expectations only apply to the other presets.
        var judged = fixture
        if preset == .quick { judged.expectedSections = [] }
        let eval = judged.evaluate(outcome.prompt)
        if eval.passed { passed += 1 }
        print("\(eval.passed ? "PASS" : "FAIL") \(fixture.id) [\(profile)/\(preset.rawValue)] \(outcome.usedModel ? "model" : "FALLBACK") \(String(format: "%.1fs", elapsed))")
        if !eval.passed { print("   \(eval.summary)") }
        if CommandLine.arguments.contains("--show") || !eval.passed {
            print(outcome.prompt.split(separator: "\n", omittingEmptySubsequences: false).map { "   │ \($0)" }.joined(separator: "\n"))
        }
        if let notice = outcome.notice { print("   notice: \(notice)") }
        if !outcome.problems.isEmpty { print("   problems: \(outcome.problems)") }
        if !outcome.dropped.isEmpty { print("   grounding dropped: \(outcome.dropped)") }
    }
    print("\n\(passed)/\(fixtures.count) passed, \(modelUsed) via model, avg \(String(format: "%.1fs", total / Double(fixtures.count))), model \(positional[1]), preset \(preset.rawValue)")

default:
    usage()
}
