import SwiftUI
import VoxaraCore

struct SettingsPage: View {
    let model: AppModel
    let openOnboarding: () -> Void
    @LocalState private var confirmClear = false

    var body: some View {
        Page(title: "Settings") {
            VStack(alignment: .leading, spacing: VX.Space.xl) {
                general
                privacy
                advanced
            }
        }
        .alert("Clear all history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { model.history.clear() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: General

    private var general: some View {
        group("General") {
            toggle("Launch at login", detail: "Start Voxara automatically so the shortcuts are always ready.",
                   Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            toggle("Show overlay", detail: "A small pill near the bottom of the screen while you speak. It never takes keyboard focus.",
                   Binding(get: { model.settings.showOverlay }, set: { model.settings.showOverlay = $0 }))
            toggle("Sound feedback", detail: "A soft tick when recording starts and stops.",
                   Binding(get: { model.settings.playSounds }, set: { model.settings.playSounds = $0 }))
            HStack {
                Text("Welcome guide").font(VX.Font.body)
                Spacer()
                Button("Open", action: openOnboarding).buttonStyle(QuietButtonStyle())
            }
        }
    }

    // MARK: Privacy

    private var privacy: some View {
        group("Privacy") {
            privacyRow("Speech transcription", status: .ok, "Local")
            privacyRow("Transcript cleanup", status: .ok, "Local")
            privacyRow("Prompt building", status: .ok, "Local")
            privacyRow("Audio storage", status: .off, "Off — recordings are discarded after transcription")
            Divider().overlay(VX.Palette.border)
            toggle("Save history", detail: "Keep the text of recent dictations and prompts on this Mac (never audio).",
                   Binding(get: { model.settings.saveHistory }, set: { model.settings.saveHistory = $0 }))
            HStack {
                Text("\(model.history.entries.count) saved entries").font(VX.Font.body).foregroundStyle(VX.Palette.textSecondary)
                Spacer()
                Button("Clear history") { confirmClear = true }.buttonStyle(QuietButtonStyle()).disabled(model.history.entries.isEmpty)
            }
            Text("Nothing is sent to any server. If a cloud provider is ever added it will be opt-in and clearly marked wherever text would leave this Mac.")
                .font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
        }
    }

    private func privacyRow(_ title: String, status: StatusKind, _ value: String) -> some View {
        HStack {
            Text(title).font(VX.Font.body).foregroundStyle(VX.Palette.textPrimary)
            Spacer()
            StatusLabel(kind: status, text: value)
        }
    }

    // MARK: Advanced

    private var advanced: some View {
        group("Advanced") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Insertion method").font(VX.Font.body)
                    Text("Paste works in practically every app and restores your clipboard afterwards.")
                        .font(VX.Font.caption).foregroundStyle(VX.Palette.textSecondary)
                }
                Spacer()
                Picker("", selection: Binding(get: { model.settings.insertionMethod }, set: { model.settings.insertionMethod = $0 })) {
                    ForEach(InsertionMethod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }.labelsHidden().frame(width: 220)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local AI model").font(VX.Font.body)
                    Text("Ollama model used for cleanup and Prompt Mode. Manage under Models.")
                        .font(VX.Font.caption).foregroundStyle(VX.Palette.textSecondary)
                }
                Spacer()
                TextField("", text: Binding(get: { model.settings.intelligenceModel }, set: { model.settings.intelligenceModel = $0 }))
                    .textFieldStyle(.roundedBorder).frame(width: 280)
            }
            Divider().overlay(VX.Palette.border)
            toggle("Test mode", detail: "Insert only into Voxara's own test window, never into other apps. Used for safe testing.",
                   Binding(get: { model.settings.testMode }, set: { model.settings.testMode = $0 }))
            HStack {
                Button("Open test window") { TestBenchWindow.shared.show(model: model) }.buttonStyle(QuietButtonStyle())
                Button("Show data folder") { NSWorkspace.shared.open(VoxaraPaths.supportDirectory) }.buttonStyle(QuietButtonStyle())
                Spacer()
            }
        }
    }

    // MARK: Helpers

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: VX.Space.md) {
            Eyebrow(title)
            Panel { VStack(alignment: .leading, spacing: VX.Space.md) { content() } }
        }
    }

    private func toggle(_ title: String, detail: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(VX.Font.body).foregroundStyle(VX.Palette.textPrimary)
                Text(detail).font(VX.Font.caption).foregroundStyle(VX.Palette.textSecondary)
            }
        }.toggleStyle(.switch)
    }
}
