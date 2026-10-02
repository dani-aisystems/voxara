import SwiftUI
import VoxaraCore

/// Reusable choice row: title + explanation, selectable.
struct ChoiceRow: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: VX.Space.md) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? VX.Palette.accent : VX.Palette.textTertiary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(VX.Font.bodyEmphasis).foregroundStyle(VX.Palette.textPrimary)
                    Text(detail).font(VX.Font.caption).foregroundStyle(VX.Palette.textSecondary).multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DictationPage: View {
    let model: AppModel
    let navigation: CommandCenterNavigation

    var body: some View {
        Page(title: "Dictation", subtitle: "Make spoken language readable without rewriting you.") {
            VStack(alignment: .leading, spacing: VX.Space.xl) {
                section("Cleanup") {
                    ForEach(CleanupLevel.allCases, id: \.self) { level in
                        ChoiceRow(title: level.displayName, detail: level.explanation, selected: model.settings.cleanup == level) {
                            model.settings.cleanup = level
                        }
                    }
                    Text("Cleanup removes fillers and stutters, resolves explicit corrections, and fixes punctuation. It never answers, summarizes or follows what you said.")
                        .font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                }

                section("Language") {
                    ForEach(SpeechLanguage.allCases, id: \.self) { language in
                        ChoiceRow(title: language.displayName, detail: Self.detail(language), selected: model.settings.language == language) {
                            model.settings.language = language
                        }
                    }
                }

                section("Technical vocabulary") {
                    Toggle(isOn: Binding(get: { model.settings.vocabularyEnabled }, set: { model.settings.vocabularyEnabled = $0 })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restore technical terms").font(VX.Font.bodyEmphasis)
                            Text("Fixes English terms that speech recognition spells phonetically in Bulgarian, like “дешбод” → dashboard.")
                                .font(VX.Font.caption).foregroundStyle(VX.Palette.textSecondary)
                        }
                    }
                    .toggleStyle(.switch)
                    Button("Edit vocabulary") { navigation.page = .vocabulary }.buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    static func detail(_ language: SpeechLanguage) -> String {
        switch language {
        case .auto: "Detects English or Bulgarian per recording and keeps English terms inside Bulgarian speech. Recommended."
        case .english: "Treat everything as English."
        case .bulgarian: "Prefer Bulgarian. Auto-detection already handles Bulgarian well, so use this only if it guesses wrong."
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: VX.Space.md) {
            Eyebrow(title)
            Panel { VStack(alignment: .leading, spacing: VX.Space.md) { content() } }
        }
    }
}
