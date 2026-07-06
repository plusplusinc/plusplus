import SwiftUI

/// The v2 "quiet-terminal" design system (issue #59, from the 2026-07-06
/// design handoff): a GitHub-dark palette with a green accent and
/// monospace for data. Dark-only by design — there is no light variant.
/// This supersedes the 2026-02-20 system-semantic-colors decision; every
/// v2 screen draws from here, never from ad-hoc color literals.
enum Theme {
    // MARK: - Palette

    /// Screen background.
    static let background = Color(hex: 0x0D1117)
    /// Cards, sheets, pills.
    static let surface = Color(hex: 0x161B22)
    /// Raised elements on a surface (menus, selected rows).
    static let surfaceRaised = Color(hex: 0x1C2129)
    /// Hairline borders on cards and rows.
    static let border = Color(hex: 0x21262D)
    /// Stronger borders (sheets, outlined buttons, chips).
    static let borderStrong = Color(hex: 0x30363D)

    static let textPrimary = Color(hex: 0xE6EDF3)
    static let textSecondary = Color(hex: 0x7D8590)
    static let textFaint = Color(hex: 0x484F58)

    /// The brand green — glyphs, highlights, captions.
    static let accent = Color(hex: 0x3FB950)
    /// Filled buttons (Start workout, Log set).
    static let accentButton = Color(hex: 0x238636)
    /// Filled-button hover/active companion.
    static let accentButtonBright = Color(hex: 0x2EA043)

    /// Superset text/badges.
    static let superset = Color(hex: 0x58A6FF)
    /// Superset rail loop stroke.
    static let supersetLine = Color(hex: 0x388BFD)

    /// Exercise/workout notes ("form cues" amber).
    static let notes = Color(hex: 0xD29922)

    static let destructive = Color(hex: 0xF85149)
    static let destructiveFill = Color(hex: 0xDA3633)

    // MARK: - Metrics

    static let cardRadius: CGFloat = 14
    static let sheetRadius: CGFloat = 20
    static let controlRadius: CGFloat = 10
}

extension Color {
    /// Color from a 0xRRGGBB literal — the palette above is specified in
    /// hex by the design and must not drift through rounding.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
