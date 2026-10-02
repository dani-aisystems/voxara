import AppKit
import SwiftUI

/// Voxara design tokens. Dark is the primary appearance; light mirrors it with the same hierarchy.
/// Views must use these tokens instead of literal colors, sizes or durations.
enum VX {
    // MARK: Spacing
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Corner radius
    enum Radius {
        static let sm: CGFloat = 5
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let pill: CGFloat = 999
    }

    // MARK: Color
    enum Palette {
        /// Orange taken from the app icon. The single accent; used sparingly.
        static let accent = dynamic(dark: 0xFB6C0C, light: 0xE35A00)
        static let accentSoft = dynamic(dark: 0xFB6C0C, light: 0xE35A00, alpha: 0.14)
        static let amber = dynamic(dark: 0xFFB020, light: 0xC77700)

        static let background = dynamic(dark: 0x0F0E0D, light: 0xFAF8F5)
        static let sidebar = dynamic(dark: 0x131211, light: 0xF1EEE9)
        static let surface = dynamic(dark: 0x1A1918, light: 0xFFFFFF)
        static let surfaceRaised = dynamic(dark: 0x232120, light: 0xF6F3EE)
        static let border = dynamic(dark: 0xF4F1EC, light: 0x1B1917, alpha: 0.09)
        static let borderStrong = dynamic(dark: 0xF4F1EC, light: 0x1B1917, alpha: 0.18)

        static let textPrimary = dynamic(dark: 0xF4F1EC, light: 0x1B1917)
        static let textSecondary = dynamic(dark: 0xA8A29A, light: 0x5E5951)
        static let textTertiary = dynamic(dark: 0x6F6A63, light: 0x8F8980)

        static let success = dynamic(dark: 0x5BC27A, light: 0x2E8B4F)
        static let warning = dynamic(dark: 0xF2B544, light: 0xB87400)
        static let error = dynamic(dark: 0xEF6A5E, light: 0xC2362A)

        static let overlayBackground = NSColor(red: 0.075, green: 0.07, blue: 0.065, alpha: 0.96)
    }

    /// The signature accent gradient, for rare emphasis only (never for body UI).
    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0xFB6C0C), Color(hex: 0xFFB020)], startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: Typography (system fonts; numbers are monospaced where they must not jitter)
    enum Font {
        static let display = SwiftUI.Font.system(size: 26, weight: .semibold)
        static let title = SwiftUI.Font.system(size: 20, weight: .semibold)
        static let headline = SwiftUI.Font.system(size: 14, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13)
        static let bodyEmphasis = SwiftUI.Font.system(size: 13, weight: .medium)
        static let caption = SwiftUI.Font.system(size: 11.5)
        static let eyebrow = SwiftUI.Font.system(size: 10.5, weight: .semibold)
        static let mono = SwiftUI.Font.system(size: 12, design: .monospaced)
        static let metric = SwiftUI.Font.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()
    }

    // MARK: Motion
    enum Motion {
        /// Overlay fades and hover feedback.
        static let fast: Double = 0.12
        static let normal: Double = 0.2
    }

    // MARK: Layout
    enum Layout {
        static let sidebarWidth: CGFloat = 196
        static let contentMaxWidth: CGFloat = 820
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

private func dynamic(dark: UInt32, light: UInt32, alpha: Double = 1) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let hex = isDark ? dark : light
        return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                       blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    })
}
