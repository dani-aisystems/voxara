import SwiftUI
import VoxaraCore

enum CommandCenterPage: String, CaseIterable, Identifiable, Hashable {
    case overview, dictation, prompt, vocabulary, history, applications, models, shortcuts, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .dictation: "Dictation"
        case .prompt: "Prompt Mode"
        case .vocabulary: "Vocabulary"
        case .history: "History"
        case .applications: "Applications"
        case .models: "Models"
        case .shortcuts: "Shortcuts"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .dictation: "text.cursor"
        case .prompt: "diamond"
        case .vocabulary: "character.book.closed"
        case .history: "clock"
        case .applications: "macwindow"
        case .models: "cpu"
        case .shortcuts: "command"
        case .settings: "gearshape"
        }
    }
}

/// Navigation state shared with the window controller so the menu can open a specific page.
@MainActor
@Observable
final class CommandCenterNavigation {
    var page: CommandCenterPage = .overview
}

struct CommandCenterView: View {
    let model: AppModel
    let navigation: CommandCenterNavigation
    let openOnboarding: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model, navigation: navigation)
            Rectangle().fill(VX.Palette.border).frame(width: 1)
            content
        }
        .background(VX.Palette.background)
        .frame(minWidth: 940, minHeight: 640)
    }

    @ViewBuilder private var content: some View {
        switch navigation.page {
        case .overview: OverviewPage(model: model, navigation: navigation, openOnboarding: openOnboarding)
        case .dictation: DictationPage(model: model, navigation: navigation)
        case .prompt: PromptPage(model: model)
        case .vocabulary: VocabularyPage(model: model)
        case .history: HistoryPage(model: model)
        case .applications: ApplicationsPage(model: model)
        case .models: ModelsPage(model: model)
        case .shortcuts: ShortcutsPage(model: model)
        case .settings: SettingsPage(model: model, openOnboarding: openOnboarding)
        }
    }
}

private struct Sidebar: View {
    let model: AppModel
    let navigation: CommandCenterNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: VX.Space.xs) {
            HStack(spacing: VX.Space.sm + 2) {
                BrandMark()
                    .frame(width: 26, height: 26)
                Text("Voxara").font(VX.Font.headline).foregroundStyle(VX.Palette.textPrimary)
            }
            .padding(.horizontal, VX.Space.md)
            .padding(.top, VX.Space.xl)
            .padding(.bottom, VX.Space.lg)

            ForEach(CommandCenterPage.allCases) { page in
                SidebarRow(page: page, selected: navigation.page == page) { navigation.page = page }
            }
            Spacer()

            HStack(spacing: VX.Space.sm) {
                StatusDot(kind: readiness.kind)
                Text(readiness.text).font(VX.Font.caption).foregroundStyle(VX.Palette.textSecondary)
            }
            .padding(VX.Space.md)
        }
        .frame(width: VX.Layout.sidebarWidth)
        .background(VX.Palette.sidebar)
    }

    private var readiness: (kind: StatusKind, text: String) {
        model.readiness
    }
}

private struct SidebarRow: View {
    let page: CommandCenterPage
    let selected: Bool
    let action: () -> Void
    @LocalState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: VX.Space.sm + 2) {
                Image(systemName: page.symbol)
                    .font(.system(size: 12))
                    .frame(width: 18)
                    .foregroundStyle(selected ? VX.Palette.accent : VX.Palette.textTertiary)
                Text(page.title).font(VX.Font.body)
                    .foregroundStyle(selected ? VX.Palette.textPrimary : VX.Palette.textSecondary)
                Spacer()
            }
            .padding(.horizontal, VX.Space.md)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: VX.Radius.md)
                    .fill(selected ? VX.Palette.surfaceRaised : (hovering ? VX.Palette.surface : .clear))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, VX.Space.sm)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: VX.Motion.fast), value: hovering)
    }
}

/// The app icon, drawn from the bundled artwork (falls back to a plain accent glyph in development builds).
struct BrandMark: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "Voxara", withExtension: "icns"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: "waveform").foregroundStyle(VX.Palette.accent)
        }
    }
}

extension AppModel {
    /// One-line summary of whether Voxara can be used right now.
    var readiness: (kind: StatusKind, text: String) {
        if !accessibilityGranted { return (.error, "Accessibility needed") }
        if !microphoneAuthorized { return (.error, "Microphone needed") }
        switch speechModelStatus {
        case .failed: return (.error, "Speech model failed")
        case .loading: return (.warning, "Loading speech model")
        case .ready: break
        }
        if settings.testMode { return (.warning, "Test mode") }
        switch ollama {
        case .running(_, true), .checking: return (.ok, "Ready")
        default: return (.warning, "Ready · basic cleanup")
        }
    }
}
