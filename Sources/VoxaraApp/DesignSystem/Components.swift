import SwiftUI

/// Small uppercase label above a group of content.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(VX.Font.eyebrow)
            .tracking(0.9)
            .foregroundStyle(VX.Palette.textTertiary)
    }
}

/// Flat bordered container. Used sparingly: most content sits directly on the background.
struct Panel<Content: View>: View {
    var padding: CGFloat = VX.Space.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VX.Palette.surface, in: RoundedRectangle(cornerRadius: VX.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: VX.Radius.lg).strokeBorder(VX.Palette.border))
    }
}

/// Page scaffold: title, optional subtitle, scrolling content with a readable maximum width.
struct Page<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VX.Space.xl) {
                VStack(alignment: .leading, spacing: VX.Space.xs) {
                    Text(title).font(VX.Font.title).foregroundStyle(VX.Palette.textPrimary)
                    if let subtitle {
                        Text(subtitle).font(VX.Font.body).foregroundStyle(VX.Palette.textSecondary)
                    }
                }
                content
            }
            .padding(VX.Space.xl)
            .frame(maxWidth: VX.Layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(VX.Palette.background)
    }
}

enum StatusKind {
    case ok, warning, error, off, active

    var color: Color {
        switch self {
        case .ok: VX.Palette.success
        case .warning: VX.Palette.warning
        case .error: VX.Palette.error
        case .off: VX.Palette.textTertiary
        case .active: VX.Palette.accent
        }
    }
}

struct StatusDot: View {
    let kind: StatusKind
    var body: some View {
        Circle().fill(kind.color).frame(width: 7, height: 7)
    }
}

/// "● Local" style indicator used by the privacy and model views.
struct StatusLabel: View {
    let kind: StatusKind
    let text: String
    var body: some View {
        HStack(spacing: VX.Space.sm - 2) {
            StatusDot(kind: kind)
            Text(text).font(VX.Font.caption).foregroundStyle(VX.Palette.textSecondary)
        }
    }
}

struct Chip: View {
    let text: String
    var tint: Color = VX.Palette.textSecondary
    var body: some View {
        Text(text)
            .font(VX.Font.eyebrow)
            .tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, VX.Space.sm)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: VX.Radius.sm))
    }
}

/// A key as it would appear on a keyboard, for shortcut display.
struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(VX.Palette.textPrimary)
            .padding(.horizontal, VX.Space.sm)
            .padding(.vertical, 3)
            .background(VX.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: VX.Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: VX.Radius.sm).strokeBorder(VX.Palette.borderStrong))
    }
}

struct MetricView: View {
    let label: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: VX.Space.xs) {
            Eyebrow(label).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(VX.Font.metric).foregroundStyle(VX.Palette.textPrimary).lineLimit(1)
            if let detail { Text(detail).font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: VX.Space.sm) {
            Text(title).font(VX.Font.headline).foregroundStyle(VX.Palette.textSecondary)
            Text(message).font(VX.Font.body).foregroundStyle(VX.Palette.textTertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(VX.Space.xxl)
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VX.Font.bodyEmphasis)
            .foregroundStyle(Color.black.opacity(0.88))
            .padding(.horizontal, VX.Space.lg)
            .padding(.vertical, VX.Space.sm - 1)
            .background(VX.Palette.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: VX.Radius.md))
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VX.Font.body)
            .foregroundStyle(VX.Palette.textPrimary)
            .padding(.horizontal, VX.Space.md)
            .padding(.vertical, VX.Space.xs + 1)
            .background(VX.Palette.surfaceRaised.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: VX.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: VX.Radius.md).strokeBorder(VX.Palette.border))
    }
}

extension View {
    /// Thin divider line in the border color.
    func hairline() -> some View {
        overlay(alignment: .bottom) { Rectangle().fill(VX.Palette.border).frame(height: 1) }
    }
}

/// `@State` is declared as a macro in recent SDKs and its compiler plugin ships only with full Xcode.
/// This alias names the underlying property-wrapper struct directly, which builds with Command Line Tools.
typealias LocalState<Value> = SwiftUI.State<Value>
