import SwiftUI
import VoxaraCore

struct ModelsPage: View {
    let model: AppModel
    @LocalState private var details: [OllamaProvider.ModelInfo] = []

    var body: some View {
        Page(title: "Models", subtitle: "Everything runs on this Mac. No audio or text leaves it.") {
            VStack(alignment: .leading, spacing: VX.Space.xl) {
                speech
                intelligence
            }
        }
        .task(id: model.settings.ollamaURL) { await loadDetails() }
    }

    private var speech: some View {
        VStack(alignment: .leading, spacing: VX.Space.md) {
            Eyebrow("Speech")
            Panel {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: VX.Space.xs) {
                        Text("Parakeet Multilingual").font(VX.Font.headline).foregroundStyle(VX.Palette.textPrimary)
                        Text("NVIDIA Parakeet TDT 0.6B v3 via FluidAudio · English, Bulgarian and 23 more languages")
                            .font(VX.Font.caption).foregroundStyle(VX.Palette.textSecondary)
                        HStack(spacing: VX.Space.lg) {
                            Chip(text: "LOCAL", tint: VX.Palette.success)
                            Text(Self.size(of: FluidModelsDirectory.url)).font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                            if let stats = speechLatency { Text("median \(stats) per recording").font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary) }
                        }
                    }
                    Spacer()
                    status
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch model.speechModelStatus {
        case .ready: StatusLabel(kind: .ok, text: "Installed · active")
        case .loading(let p): StatusLabel(kind: .warning, text: p.map { "Downloading \(Int($0 * 100))%" } ?? "Loading…")
        case .failed(let why):
            VStack(alignment: .trailing, spacing: VX.Space.sm) {
                StatusLabel(kind: .error, text: why)
                Button("Retry") { Task { await model.loadSpeechModel() } }.buttonStyle(QuietButtonStyle())
            }
        }
    }

    private var speechLatency: String? {
        UsageStats.compute(model.history.entries).medianSTT.map(OverviewPage.seconds)
    }

    private var intelligence: some View {
        VStack(alignment: .leading, spacing: VX.Space.md) {
            Eyebrow("Intelligence")
            Panel(padding: 0) {
                VStack(spacing: 0) {
                    switch model.ollama {
                    case .checking:
                        row(title: "Checking Ollama…", detail: "", active: false, installed: false, action: nil)
                    case .unavailable(let why):
                        VStack(alignment: .leading, spacing: VX.Space.sm) {
                            StatusLabel(kind: .warning, text: why)
                            Text("Dictation still works with rule-based cleanup. Start Ollama (brew services start ollama) to enable AI cleanup and Prompt Mode.")
                                .font(VX.Font.caption).foregroundStyle(VX.Palette.textSecondary)
                        }.padding(VX.Space.lg)
                    case .running:
                        if details.isEmpty {
                            Text("No models installed.").font(VX.Font.body).foregroundStyle(VX.Palette.textTertiary).padding(VX.Space.lg)
                        }
                        ForEach(details) { info in
                            row(title: OverviewPage.displayName(info.name), detail: "\(info.name) · \(Self.format(info.bytes))",
                                active: info.name == model.settings.intelligenceModel, installed: true) {
                                model.settings.intelligenceModel = info.name
                            }
                            Divider().overlay(VX.Palette.border)
                        }
                    }
                }
            }
            HStack(spacing: VX.Space.lg) {
                Chip(text: "LOCAL", tint: VX.Palette.success)
                if let cleanup = UsageStats.compute(model.history.entries).medianCleanup {
                    Text("Cleanup median \(OverviewPage.seconds(cleanup))").font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                }
                if let prompt = UsageStats.compute(model.history.entries).medianPrompt {
                    Text("Prompt median \(OverviewPage.seconds(prompt))").font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                }
            }
            Text("Voxara talks to Ollama at \(model.settings.ollamaURL). Text sent for cleanup or prompt building never leaves this Mac. Cloud providers are not enabled.")
                .font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
        }
    }

    private func row(title: String, detail: String, active: Bool, installed: Bool, action: (() -> Void)?) -> some View {
        HStack(spacing: VX.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(VX.Font.bodyEmphasis).foregroundStyle(VX.Palette.textPrimary)
                Text(detail).font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
            }
            Spacer()
            if active { StatusLabel(kind: .ok, text: "Active") }
            else if let action { Button("Use this", action: action).buttonStyle(QuietButtonStyle()) }
        }
        .padding(VX.Space.lg)
    }

    private func loadDetails() async {
        let provider = OllamaProvider(baseURL: URL(string: model.settings.ollamaURL) ?? URL(string: "http://127.0.0.1:11434")!, model: model.settings.intelligenceModel)
        details = ((try? await provider.installedModelDetails()) ?? []).sorted { $0.name < $1.name }
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func size(of url: URL) -> String {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return "—" }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total > 0 ? format(total) : "—"
    }
}

enum FluidModelsDirectory {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models/parakeet-tdt-0.6b-v3")
    }
}
