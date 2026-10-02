import AppKit
import SwiftUI
import VoxaraCore

struct ShortcutsPage: View {
    let model: AppModel

    var body: some View {
        Page(title: "Shortcuts", subtitle: "Hold to talk: press and hold, speak, release.") {
            VStack(alignment: .leading, spacing: VX.Space.xl) {
                Panel {
                    VStack(alignment: .leading, spacing: VX.Space.lg) {
                        ShortcutRecorderRow(
                            model: model, title: "Dictation", detail: "Voice → clean text, inserted where your cursor is.", glyph: "●",
                            shortcut: Binding(get: { model.settings.dictationShortcut }, set: { model.settings.dictationShortcut = $0 })
                        )
                        Divider().overlay(VX.Palette.border)
                        ShortcutRecorderRow(
                            model: model, title: "Prompt", detail: "Voice → structured AI instruction.", glyph: "◆",
                            shortcut: Binding(get: { model.settings.promptShortcut }, set: { model.settings.promptShortcut = $0 })
                        )
                        if let conflict = model.shortcutConflict {
                            Text(conflict).font(VX.Font.caption).foregroundStyle(VX.Palette.error)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: VX.Space.md) {
                    Eyebrow("How it works")
                    Panel {
                        VStack(alignment: .leading, spacing: VX.Space.sm) {
                            bullet("Recording starts the instant you press, so the first word is never lost.")
                            bullet("Press any other key while holding and Voxara quietly cancels, so shortcuts like Right ⌘ + C still work.")
                            bullet("Taps shorter than a quarter second are ignored as accidents.")
                            bullet("Press Esc while holding to cancel a recording.")
                            bullet("Right-side modifiers are recommended: they do not interfere with typing.")
                        }
                    }
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: VX.Space.sm) {
            Text("·").foregroundStyle(VX.Palette.textTertiary)
            Text(text).font(VX.Font.body).foregroundStyle(VX.Palette.textSecondary)
        }
    }
}

private struct ShortcutRecorderRow: View {
    let model: AppModel
    let title: String
    let detail: String
    let glyph: String
    @Binding var shortcut: Shortcut
    @LocalState private var recording = false
    @LocalState private var monitor: Any?
    @LocalState private var held: Set<ModifierKey> = []
    @LocalState private var peak: Set<ModifierKey> = []

    var body: some View {
        VStack(alignment: .leading, spacing: VX.Space.sm) {
            HStack(spacing: VX.Space.md) {
                Text(glyph).font(.system(size: 11)).foregroundStyle(VX.Palette.accent).frame(width: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(VX.Font.bodyEmphasis).foregroundStyle(VX.Palette.textPrimary)
                    Text(detail).font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                }
                Spacer()
                if recording {
                    Text("Press the key or combination…").font(VX.Font.caption).foregroundStyle(VX.Palette.accent)
                    Button("Cancel", action: stop).buttonStyle(QuietButtonStyle())
                } else {
                    ShortcutCaps(shortcut: shortcut)
                    Button("Change") { start() }.buttonStyle(QuietButtonStyle())
                }
            }
            if let warning = ShortcutValidation.warning(for: shortcut) {
                Text(warning).font(VX.Font.caption).foregroundStyle(VX.Palette.warning).padding(.leading, VX.Space.xl)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        held = []
        peak = []
        model.pauseHotkeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { model.resumeHotkeys() }
        recording = false
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == KeyNames.escape { stop(); return }
            let modifiers = ModifierKey.held(in: UInt64(event.cgEvent?.flags.rawValue ?? 0))
            // A plain key with no modifier would block typing that key everywhere.
            guard !modifiers.isEmpty else { NSSound.beep(); return }
            shortcut = .combo(keyCode: event.keyCode, modifiers: modifiers)
            stop()
            return
        }
        // Modifier-only: remember the largest chord, accept when everything is released.
        held = ModifierKey.held(in: UInt64(event.cgEvent?.flags.rawValue ?? 0))
        if held.count > peak.count { peak = held }
        if held.isEmpty, peak.count == 1, let key = peak.first {
            shortcut = .modifier(key)
            stop()
        } else if held.isEmpty {
            peak = []
        }
    }
}
