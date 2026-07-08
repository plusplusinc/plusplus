import SwiftUI
import UIKit

/// The v3 "ink × increment green" design system (issue #108, Claude
/// Design handoff §1), superseding the v2 GitHub palette. Chrome is
/// monochrome ink; full-chroma green is reserved for the data — deltas,
/// net chips, committed timeline nodes, next-due values, and the ++
/// glyph. Every screen draws from here, never from ad-hoc color
/// literals; the appearance setting (AppAppearance) decides which side
/// of each pair renders.
enum Theme {
    // MARK: - Palette (light / dark)

    /// Screen background.
    static let background = Color(light: 0xFFFFFF, dark: 0x141414)
    /// Cards, sheets, pills.
    static let surface = Color(light: 0xF4F3F1, dark: 0x1C1C1C)
    /// Raised elements on a surface (menus, selected rows).
    static let surfaceRaised = Color(light: 0xEAE8E4, dark: 0x242424)
    /// Hairline borders on cards and rows.
    static let border = Color(light: 0xDDDBD7, dark: 0x292929)
    /// Stronger borders (sheets, outlined buttons, chips).
    static let borderStrong = Color(light: 0xC2C0BA, dark: 0x383838)

    static let textPrimary = Color(light: 0x232220, dark: 0xF0EDE6)
    static let textSecondary = Color(light: 0x6B6965, dark: 0x9D9B96)
    static let textFaint = Color(light: 0x767370, dark: 0x8A8781)

    /// The data green. Green is data, never chrome: deltas, net chips,
    /// "new" markers, next-due values, live progress, and the ++ glyph.
    static let accent = Color(light: 0x17914B, dark: 0x46D17C)
    /// Committed timeline nodes on the Today rail.
    static let committedFill = Color(light: 0x1E9E54, dark: 0x46D17C)

    /// Interactive/selected state (v4 §1): blue is UI state — which
    /// option is active. Never a data color, never an action fill.
    /// Light uses the darker cousin: #62B6DE is ~2.2:1 on white.
    static let selected = Color(light: 0x1A7FA8, dark: 0x62B6DE)
    /// Content on a SOLID selected fill — rare; prefer the tint
    /// treatment. Never white on #62B6DE.
    static let onSelected = Color(light: 0xFFFFFF, dark: 0x161616)
    /// Selected-state fill; always accompanied by `selectedRing`.
    static let selectedTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: 0x62B6DE).withAlphaComponent(0.16)
            : UIColor(hex: 0x1A7FA8).withAlphaComponent(0.12)
    })
    /// 1 pt border accompanying every selectedTint fill.
    static let selectedRing = selected.opacity(0.55)

    /// Filled controls — Start/Continue/Log set, Done capsules, setup
    /// CTAs: ink in light, cream in dark. Actions, never selection.
    static let primaryFill = Color(light: 0x232220, dark: 0xF0EDE6)
    /// Text and glyphs sitting on primaryFill.
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x161616)

    /// Exercise/routine notes ("form cues" amber).
    static let notes = Color(light: 0x9A6700, dark: 0xCFA14A)

    static let destructive = Color(light: 0xCF222E, dark: 0xE5534B)

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
