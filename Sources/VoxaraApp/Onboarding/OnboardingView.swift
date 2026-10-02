import SwiftUI
import VoxaraCore

struct OnboardingView: View {
    let model: AppModel
    let finish: () -> Void
    @LocalState private var step = Step.welcome
    @LocalState private var testText = ""

    enum Step: Int, CaseIterable {
        case welcome, modes, microphone, accessibility, speech, shortcuts, test
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                content
                    .id(step)
                    .transition(.opacity)
            }
            .animation(.easeOut(duration: VX.Motion.normal), value: step)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, VX.Space.xxl + VX.Space.lg)

            footer
        }
        .frame(width: 640, height: 520)
        .background(VX.Palette.background)
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            VStack(spacing: VX.Space.lg) {
                BrandMark().frame(width: 96, height: 96)
                Text("Meet Voxara").font(VX.Font.display).foregroundStyle(VX.Palette.textPrimary)
                Text("Speak naturally anywhere on your Mac.").font(VX.Font.headline).foregroundStyle(VX.Palette.textSecondary)
                Text("Everything runs on this Mac. No account, nothing uploaded.").font(VX.Font.body).foregroundStyle(VX.Palette.textTertiary)
            }

        case .modes:
            VStack(alignment: .leading, spacing: VX.Space.xl) {
                title("Two ways to talk")
                modeCard(glyph: "●", name: "DICTATE", detail: "Voice → clean text", example: "“um so I think we should, actually, ship it Tuesday” → “I think we should ship it Tuesday.”")
                modeCard(glyph: "◆", name: "PROMPT", detail: "Voice → structured AI instruction", example: "Rambling thoughts become a clear prompt for Claude, ChatGPT or Claude Code.")
            }

        case .microphone:
            permission(
                title: "Microphone", why: "Voxara records only while you hold the shortcut, and the audio is discarded right after it is transcribed.",
                granted: model.microphoneAuthorized, buttonTitle: AudioRecorder.permission == .denied ? "Open System Settings" : "Allow microphone"
            ) {
                if AudioRecorder.permission == .denied { Permissions.openMicrophoneSettings() } else { Task { await model.prepareMicrophone() } }
            }

        case .accessibility:
            permission(
                title: "Accessibility", why: "Needed to hear the global shortcut and to type the result into the app you are using. Voxara never reads what is on your screen.",
                granted: model.accessibilityGranted, buttonTitle: "Open System Settings"
            ) {
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
            }

        case .speech:
            VStack(alignment: .leading, spacing: VX.Space.lg) {
                title("Speech")
                Text("Primary: English · Secondary: Bulgarian").font(VX.Font.headline).foregroundStyle(VX.Palette.textPrimary)
                Text("One multilingual model handles both and switches automatically, including English technical terms inside Bulgarian sentences.")
                    .font(VX.Font.body).foregroundStyle(VX.Palette.textSecondary)
                Panel {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Parakeet Multilingual").font(VX.Font.bodyEmphasis).foregroundStyle(VX.Palette.textPrimary)
                            Text("About 460 MB · runs on this Mac").font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                        }
                        Spacer()
                        switch model.speechModelStatus {
                        case .ready: StatusLabel(kind: .ok, text: "Ready")
                        case .loading(let p): StatusLabel(kind: .warning, text: p.map { "Downloading \(Int($0 * 100))%" } ?? "Preparing…")
                        case .failed(let why): StatusLabel(kind: .error, text: why)
                        }
                    }
                }
                if case .loading(let p?) = model.speechModelStatus { ProgressView(value: p).tint(VX.Palette.accent) }
            }

        case .shortcuts:
            VStack(alignment: .leading, spacing: VX.Space.lg) {
                title("Hold to talk")
                Panel {
                    VStack(alignment: .leading, spacing: VX.Space.md) {
                        row("●", "Dictation", model.settings.dictationShortcut)
                        row("◆", "Prompt", model.settings.promptShortcut)
                    }
                }
                Text("Press and hold, speak, then release. Change these any time under Shortcuts.")
                    .font(VX.Font.body).foregroundStyle(VX.Palette.textSecondary)
            }

        case .test:
            VStack(alignment: .leading, spacing: VX.Space.lg) {
                title("Try it")
                Text("Click in the box, hold \(model.settings.dictationShortcut.displayName.replacingOccurrences(of: "Hold ", with: "")) and say something.")
                    .font(VX.Font.body).foregroundStyle(VX.Palette.textSecondary)
                TextEditor(text: $testText)
                    .font(VX.Font.body).scrollContentBackground(.hidden)
                    .padding(VX.Space.sm)
                    .frame(height: 150)
                    .background(VX.Palette.surface, in: RoundedRectangle(cornerRadius: VX.Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: VX.Radius.md).strokeBorder(VX.Palette.borderStrong))
                if !testText.isEmpty {
                    StatusLabel(kind: .ok, text: "It works. Voxara types into any text field the same way.")
                }
            }
        }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(VX.Font.title).foregroundStyle(VX.Palette.textPrimary)
    }

    private func modeCard(glyph: String, name: String, detail: String, example: String) -> some View {
        Panel {
            HStack(alignment: .top, spacing: VX.Space.md) {
                Text(glyph).font(.system(size: 13)).foregroundStyle(VX.Palette.accent).padding(.top, 2)
                VStack(alignment: .leading, spacing: VX.Space.xs) {
                    HStack(spacing: VX.Space.sm) {
                        Text(name).font(VX.Font.eyebrow).tracking(1).foregroundStyle(VX.Palette.accent)
                        Text(detail).font(VX.Font.bodyEmphasis).foregroundStyle(VX.Palette.textPrimary)
                    }
                    Text(example).font(VX.Font.caption).foregroundStyle(VX.Palette.textSecondary)
                }
            }
        }
    }

    private func row(_ glyph: String, _ title: String, _ shortcut: Shortcut) -> some View {
        HStack(spacing: VX.Space.md) {
            Text(glyph).font(.system(size: 11)).foregroundStyle(VX.Palette.accent)
            Text(title).font(VX.Font.bodyEmphasis).foregroundStyle(VX.Palette.textPrimary)
            Spacer()
            ShortcutCaps(shortcut: shortcut)
        }
    }

    private func permission(title text: String, why: String, granted: Bool, buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: VX.Space.lg) {
            title(text)
            Text(why).font(VX.Font.body).foregroundStyle(VX.Palette.textSecondary)
            HStack(spacing: VX.Space.md) {
                if granted {
                    StatusLabel(kind: .ok, text: "\(text) allowed")
                } else {
                    Button(buttonTitle, action: action).buttonStyle(AccentButtonStyle())
                    StatusLabel(kind: .warning, text: "Waiting…")
                }
            }
        }
    }

    // MARK: Footer

    private var canContinue: Bool {
        switch step {
        case .microphone: model.microphoneAuthorized
        case .accessibility: model.accessibilityGranted
        default: true
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Circle().fill(s == step ? VX.Palette.accent : VX.Palette.borderStrong).frame(width: 6, height: 6)
                }
            }
            Spacer()
            if step != .welcome { Button("Back") { move(-1) }.buttonStyle(QuietButtonStyle()) }
            if step == .microphone || step == .accessibility, !canContinue {
                Button("Skip for now") { move(1) }.buttonStyle(.plain).font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
            }
            if step == .test {
                Button("Finish") { finish() }.buttonStyle(AccentButtonStyle())
            } else {
                Button(step == .welcome ? "Get started" : "Continue") { move(1) }
                    .buttonStyle(AccentButtonStyle()).opacity(canContinue ? 1 : 0.5).disabled(!canContinue)
            }
        }
        .padding(VX.Space.lg)
        .overlay(alignment: .top) { Rectangle().fill(VX.Palette.border).frame(height: 1) }
    }

    private func move(_ delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) { step = next }
    }
}
