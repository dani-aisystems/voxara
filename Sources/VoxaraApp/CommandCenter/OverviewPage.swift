import SwiftUI
import VoxaraCore

/// The cockpit: is everything operational, what are the shortcuts, how fast has it been, what was produced.
struct OverviewPage: View {
    let model: AppModel
    let navigation: CommandCenterNavigation
    let openOnboarding: () -> Void

    var body: some View {
        Page(title: "Overview") {
            VStack(alignment: .leading, spacing: VX.Space.xl) {
                statusHeader
                if !model.accessibilityGranted || !model.microphoneAuthorized { setupNotice }
                HStack(alignment: .top, spacing: VX.Space.lg) {
                    shortcutsPanel
                    engines
                }
                today
                recent
            }
        }
    }

    // MARK: Status

    private var statusHeader: some View {
        let r = model.readiness
        return HStack(spacing: VX.Space.md) {
            StatusDot(kind: r.kind)
            Text(r.text).font(VX.Font.headline).foregroundStyle(VX.Palette.textPrimary)
            Spacer()
            readinessItem("Microphone", ok: model.microphoneAuthorized)
            readinessItem("Accessibility", ok: model.accessibilityGranted)
            readinessItem("Speech", ok: model.speechModelStatus == .ready)
            readinessItem("Local AI", ok: { if case .running(_, true) = model.ollama { true } else { false } }())
        }
    }

    private func readinessItem(_ title: String, ok: Bool) -> some View {
        StatusLabel(kind: ok ? .ok : .warning, text: title)
    }

    private var setupNotice: some View {
        Panel {
            HStack(spacing: VX.Space.lg) {
                VStack(alignment: .leading, spacing: VX.Space.xs) {
                    Text("Finish setup").font(VX.Font.headline).foregroundStyle(VX.Palette.textPrimary)
                    Text("Voxara needs Microphone and Accessibility access to hear you and to type into other apps.")
                        .font(VX.Font.body).foregroundStyle(VX.Palette.textSecondary)
                }
                Spacer()
                Button("Open setup guide", action: openOnboarding).buttonStyle(AccentButtonStyle())
            }
        }
    }

    // MARK: Shortcuts

    private var shortcutsPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: VX.Space.md) {
                Eyebrow("Hold to talk")
                shortcutRow(model.settings.dictationShortcut, title: "Dictation", detail: "Voice → clean text", glyph: "●")
                shortcutRow(model.settings.promptShortcut, title: "Prompt", detail: "Voice → structured AI instruction", glyph: "◆")
                Divider().overlay(VX.Palette.border)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow("Prompt profile")
                        Text(model.profiles.profile(model.settings.promptProfile).name)
                            .font(VX.Font.bodyEmphasis).foregroundStyle(VX.Palette.textPrimary)
                    }
                    Spacer()
                    Menu {
                        ForEach(model.profiles.ordered) { profile in
                            Button(profile.name) { model.settings.promptProfile = profile.id }
                        }
                    } label: { Text("Change") }
                        .menuStyle(.borderlessButton).fixedSize()
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow("Preset")
                        Text(model.settings.promptPreset.displayName).font(VX.Font.bodyEmphasis).foregroundStyle(VX.Palette.textPrimary)
                    }
                    Spacer()
                    Picker("", selection: Binding(get: { model.settings.promptPreset }, set: { model.settings.promptPreset = $0 })) {
                        ForEach(PromptPreset.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                }
            }
        }
    }

    private func shortcutRow(_ shortcut: Shortcut, title: String, detail: String, glyph: String) -> some View {
        HStack(spacing: VX.Space.md) {
            Text(glyph).font(.system(size: 11)).foregroundStyle(VX.Palette.accent).frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(VX.Font.bodyEmphasis).foregroundStyle(VX.Palette.textPrimary)
                Text(detail).font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
            }
            Spacer()
            ShortcutCaps(shortcut: shortcut)
        }
    }

    // MARK: Engines

    private var engines: some View {
        Panel {
            VStack(alignment: .leading, spacing: VX.Space.md) {
                Eyebrow("Speech")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Parakeet Multilingual").font(VX.Font.bodyEmphasis).foregroundStyle(VX.Palette.textPrimary)
                    Text("English + Bulgarian · on this Mac").font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                }
                speechStatus
                Divider().overlay(VX.Palette.border)
                Eyebrow("Intelligence")
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.displayName(model.settings.intelligenceModel)).font(VX.Font.bodyEmphasis).foregroundStyle(VX.Palette.textPrimary)
                    Text("Ollama · on this Mac").font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                }
                intelligenceStatus
            }
        }
    }

    @ViewBuilder private var speechStatus: some View {
        switch model.speechModelStatus {
        case .ready: StatusLabel(kind: .ok, text: "Installed · active")
        case .loading(let p): StatusLabel(kind: .warning, text: p.map { "Downloading \(Int($0 * 100))%" } ?? "Loading…")
        case .failed(let why): StatusLabel(kind: .error, text: why)
        }
    }

    @ViewBuilder private var intelligenceStatus: some View {
        switch model.ollama {
        case .checking: StatusLabel(kind: .off, text: "Checking…")
        case .unavailable(let why): StatusLabel(kind: .warning, text: "\(why) · basic cleanup only")
        case .running(_, let ready): StatusLabel(kind: ready ? .ok : .warning, text: ready ? "Installed · active" : "Model not installed")
        }
    }

    static func displayName(_ ollamaModel: String) -> String {
        let base = ollamaModel.split(separator: ":").first.map(String.init) ?? ollamaModel
        let tag = ollamaModel.split(separator: ":").dropFirst().first.map(String.init) ?? ""
        let size = tag.split(separator: "-").first(where: { $0.hasSuffix("b") && $0.dropLast().allSatisfy(\.isNumber) }).map { " \($0.dropLast())B" } ?? ""
        return base.prefix(1).uppercased() + base.dropFirst() + size
    }

    // MARK: Today

    private var today: some View {
        let stats = UsageStats.today(model.history.entries)
        return VStack(alignment: .leading, spacing: VX.Space.md) {
            Eyebrow("Today")
            if stats.count == 0 {
                Panel {
                    Text("Nothing yet today. Hold \(model.settings.dictationShortcut.displayName.replacingOccurrences(of: "Hold ", with: "")) and speak.")
                        .font(VX.Font.body).foregroundStyle(VX.Palette.textTertiary)
                }
            } else {
                Panel {
                    HStack(alignment: .top, spacing: VX.Space.lg) {
                        MetricView(label: "Dictations", value: "\(stats.dictations)", detail: stats.prompts > 0 ? "+ \(stats.prompts) prompt\(stats.prompts == 1 ? "" : "s")" : nil)
                        MetricView(label: "Spoken", value: Self.minutes(stats.secondsSpoken))
                        MetricView(label: "Transcription", value: Self.seconds(stats.medianSTT), detail: "median")
                        MetricView(label: "Cleanup", value: Self.seconds(stats.medianCleanup), detail: stats.medianCleanup == nil ? "no model runs" : "median, AI runs")
                        MetricView(label: "Prompt", value: Self.seconds(stats.medianPrompt), detail: stats.medianPrompt == nil ? "none yet" : "median")
                    }
                }
            }
        }
    }

    static func seconds(_ value: TimeInterval?) -> String {
        guard let value else { return "—" }
        return value < 1 ? String(format: "%.2f s", value) : String(format: "%.1f s", value)
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "\(Int(seconds)) s" : String(format: "%.1f min", seconds / 60)
    }

    // MARK: Recent

    private var recent: some View {
        VStack(alignment: .leading, spacing: VX.Space.md) {
            HStack {
                Eyebrow("Recent")
                Spacer()
                if !model.history.entries.isEmpty {
                    Button("All history") { navigation.page = .history }.buttonStyle(.plain)
                        .font(VX.Font.caption).foregroundStyle(VX.Palette.textSecondary)
                }
            }
            if model.history.entries.isEmpty {
                Panel { Text("Your dictations and prompts will appear here. Audio is never saved.")
                    .font(VX.Font.body).foregroundStyle(VX.Palette.textTertiary) }
            } else {
                Panel(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(model.history.entries.prefix(5)) { entry in
                            HistoryRow(entry: entry).padding(.horizontal, VX.Space.lg).padding(.vertical, VX.Space.md)
                            if entry.id != model.history.entries.prefix(5).last?.id { Divider().overlay(VX.Palette.border) }
                        }
                    }
                }
            }
        }
    }
}

/// Shortcut as keycaps: "Hold" + the key.
struct ShortcutCaps: View {
    let shortcut: Shortcut
    var body: some View {
        HStack(spacing: VX.Space.xs) {
            switch shortcut {
            case .modifier(let key):
                Text("Hold").font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                KeyCap(text: key.displayName)
            case .combo:
                KeyCap(text: shortcut.displayName)
            }
        }
    }
}
