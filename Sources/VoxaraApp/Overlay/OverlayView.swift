import SwiftUI
import VoxaraCore

/// The compact status pill. Understated on purpose: one glyph, one short label, an optional meter.
struct OverlayView: View {
    let model: AppModel

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            pill
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pill: some View {
        HStack(spacing: VX.Space.sm + 2) {
            glyph
            Text(label)
                .font(VX.Font.bodyEmphasis)
                .foregroundStyle(VX.Palette.textPrimary)
                .lineLimit(1)
            trailing
        }
        .padding(.horizontal, VX.Space.lg - 2)
        .frame(height: 34)
        .background(Color(nsColor: VX.Palette.overlayBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        .animation(.easeOut(duration: VX.Motion.fast), value: model.pipelineState)
    }

    // MARK: State → presentation

    private var mode: HotkeyAction? {
        switch model.pipelineState {
        case .listening(let m, _), .transcribing(let m), .processing(let m, _), .done(let m, _, _): m
        default: nil
        }
    }

    @ViewBuilder private var glyph: some View {
        switch model.pipelineState {
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(VX.Palette.warning)
        case .done:
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(VX.Palette.success)
        default:
            // ● dictation, ◆ prompt — the only place the mode is shown.
            Text(mode == .prompt ? "◆" : "●")
                .font(.system(size: mode == .prompt ? 11 : 10))
                .foregroundStyle(VX.Palette.accent)
        }
    }

    private var label: String {
        switch model.pipelineState {
        case .idle: ""
        case .listening: "Listening"
        case .transcribing: "Transcribing…"
        case .processing(_, .refining): "Refining…"
        case .processing(_, .buildingPrompt): "Building prompt…"
        case .done(let m, _, let notice):
            notice ?? (m == .prompt ? "Prompt inserted" : "Inserted")
        case .failed(let message, _): message
        }
    }

    @ViewBuilder private var trailing: some View {
        if case .listening(_, let started) = model.pipelineState {
            LevelMeter(levels: model.levels)
            TimelineView(.periodic(from: started, by: 0.5)) { context in
                let seconds = Int(context.date.timeIntervalSince(started))
                Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                    .font(VX.Font.caption.monospacedDigit())
                    .foregroundStyle(VX.Palette.textSecondary)
            }
        }
    }

    private var borderColor: Color {
        if case .failed = model.pipelineState { return VX.Palette.warning.opacity(0.5) }
        if case .listening = model.pipelineState { return VX.Palette.accent.opacity(0.45) }
        return VX.Palette.border
    }
}

/// Seven-ish thin bars driven by real microphone level; no decorative animation.
struct LevelMeter: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(VX.Palette.accent.opacity(0.35 + 0.65 * Double(level)))
                    .frame(width: 2.5, height: 4 + 14 * CGFloat(level))
            }
        }
        .frame(height: 18)
        .animation(.linear(duration: 0.08), value: levels)
    }
}
