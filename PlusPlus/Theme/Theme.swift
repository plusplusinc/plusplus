import SwiftUI
import UIKit

/// The v2 "quiet-terminal" design system (issue #59), now adaptive
/// (#97): a GitHub-dark palette with a green accent and monospace for
/// data, paired with its GitHub-light sibling. Every screen draws from
/// here, never from ad-hoc color literals; the appearance setting
/// (AppAppearance) decides which side of each pair renders.
enum Theme {
    // MARK: - Palette (light / dark)

    /// Screen background.
    static let background = Color(light: 0xFFFFFF, dark: 0x0D1117)
    /// Cards, sheets, pills.
    static let surface = Color(light: 0xF6F8FA, dark: 0x161B22)
    /// Raised elements on a surface (menus, selected rows).
    static let surfaceRaised = Color(light: 0xEAEEF2, dark: 0x1C2129)
    /// Hairline borders on cards and rows.
    static let border = Color(light: 0xD0D7DE, dark: 0x21262D)
    /// Stronger borders (sheets, outlined buttons, chips).
    static let borderStrong = Color(light: 0xAFB8C1, dark: 0x30363D)

    static let textPrimary = Color(light: 0x1F2328, dark: 0xE6EDF3)
    static let textSecondary = Color(light: 0x59636E, dark: 0x7D8590)
    static let textFaint = Color(light: 0x818B98, dark: 0x484F58)

    /// The brand green — glyphs, highlights, captions.
    static let accent = Color(light: 0x1A7F37, dark: 0x3FB950)
    /// Filled buttons (Start workout, Log set).
    static let accentButton = Color(light: 0x2DA44E, dark: 0x238636)
    /// Filled-button hover/active companion.
    static let accentButtonBright = Color(light: 0x2C974B, dark: 0x2EA043)

    /// Text and glyphs sitting on filled accent/destructive buttons —
    /// white on both palettes, matching GitHub's filled buttons.
    static let onAccent = Color.white

    /// Superset text/badges.
    static let superset = Color(light: 0x0969DA, dark: 0x58A6FF)
    /// Superset rail loop stroke.
    static let supersetLine = Color(light: 0x218BFF, dark: 0x388BFD)

    /// Exercise/workout notes ("form cues" amber).
    static let notes = Color(light: 0x9A6700, dark: 0xD29922)

    static let destructive = Color(light: 0xCF222E, dark: 0xF85149)
    static let destructiveFill = Color(light: 0xA40E26, dark: 0xDA3633)

    // MARK: - Metrics

    static let cardRadius: CGFloat = 14
    static let sheetRadius: CGFloat = 20
    static let controlRadius: CGFloat = 10
}

extension Color {
    /// Color from a 0xRRGGBB literal — palette values are specified in
    /// hex by the design and must not drift through rounding.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// An adaptive pair resolved by the environment's color scheme —
    /// works everywhere Color does, including Canvas drawing.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
