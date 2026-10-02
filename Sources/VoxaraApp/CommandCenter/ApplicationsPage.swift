import SwiftUI
import VoxaraCore

struct ApplicationsPage: View {
    let model: AppModel

    var body: some View {
        Page(title: "Applications", subtitle: "How Voxara behaves in each app. Your hotkey always decides Dictation or Prompt; these settings only adjust the profile and cleanup.") {
            VStack(alignment: .leading, spacing: VX.Space.lg) {
                if model.appPreferences.sorted.isEmpty {
                    Panel { EmptyState(title: "No apps yet", message: "Apps appear here the first time you use Voxara in them.") }
                } else {
                    ForEach(model.appPreferences.sorted) { pref in
                        AppCard(model: model, pref: pref)
                    }
                }
                Text("Suggestions are conservative: a profile may be suggested for Terminal, editors, ChatGPT and Claude, and messaging apps get lighter cleanup. Anything you set here overrides the suggestion.")
                    .font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
            }
        }
    }
}

private struct AppCard: View {
    let model: AppModel
    let pref: AppPreference

    private var suggestion: AppSuggestion? { AppCatalog.suggestion(bundleID: pref.bundleID) }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: VX.Space.md) {
                HStack(spacing: VX.Space.md) {
                    AppIcon(bundleID: pref.bundleID).frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pref.displayName).font(VX.Font.bodyEmphasis).foregroundStyle(VX.Palette.textPrimary)
                        Text(suggestion.map { "Suggested: \($0.category)" } ?? pref.bundleID)
                            .font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                    }
                    Spacer()
                    Button("Forget") { model.appPreferences.remove(pref.bundleID) }.buttonStyle(.plain)
                        .font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                }
                HStack(spacing: VX.Space.xl) {
                    labelled("Prompt profile") {
                        Picker("", selection: Binding(get: { pref.promptProfile ?? "" }, set: { newValue in
                            var p = pref; p.promptProfile = newValue.isEmpty ? nil : newValue; model.appPreferences.update(p)
                        })) {
                            Text(defaultLabel).tag("")
                            ForEach(model.profiles.ordered) { Text($0.name).tag($0.id) }
                        }.labelsHidden()
                    }
                    labelled("Dictation cleanup") {
                        Picker("", selection: Binding(get: { pref.cleanup?.rawValue ?? "" }, set: { newValue in
                            var p = pref; p.cleanup = CleanupLevel(rawValue: newValue); model.appPreferences.update(p)
                        })) {
                            Text("Automatic").tag("")
                            ForEach(CleanupLevel.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
                        }.labelsHidden()
                    }
                }
                Toggle(isOn: Binding(get: { pref.dictationKeyProducesPrompt }, set: { newValue in
                    var p = pref; p.dictationKeyProducesPrompt = newValue; model.appPreferences.update(p)
                })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Dictation key builds a prompt in this app").font(VX.Font.body)
                        Text("Off by default. Turn on only for apps where you always want prompts.")
                            .font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                    }
                }.toggleStyle(.switch)
            }
        }
    }

    private var defaultLabel: String {
        if let name = suggestion?.promptProfile { return "Automatic (\(ProfileNames.display(name)))" }
        return "Automatic (\(ProfileNames.display(model.settings.promptProfile)))"
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: VX.Space.xs) { Eyebrow(title); content().frame(width: 210, alignment: .leading) }
    }
}

struct AppIcon: View {
    let bundleID: String
    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            Image(systemName: "app").foregroundStyle(VX.Palette.textTertiary)
        }
    }
}
