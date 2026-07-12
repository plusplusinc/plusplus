import SwiftUI
import UIKit

/// The "Quiet Arcade" refresh (2026-07-10 handoff) of the v3 "ink ×
/// increment green" system: same warm paper/ink neutrals and hue jobs,
/// plus physical press mechanics (RaisedKey), a brighter selection
/// blue, and a softened warm-charcoal dark mode. Chrome is monochrome
/// ink; full-chroma green is reserved for the data — deltas, net
/// chips, "new" markers, ready rail rings, live progress, creation
/// rows, and the ++ glyph. Every screen draws from here, never from
/// ad-hoc color literals; the appearance setting (AppAppearance)
/// decides which side of each pair renders.
enum Theme {
    // MARK: - Palette (light / dark)

    /// Screen background. Dark is warm charcoal, not OLED black.
    static let background = Color(light: 0xFFFFFF, dark: 0x201F1D)
    /// Cards, sheets, pills.
    static let surface = Color(light: 0xF4F3F1, dark: 0x2A2925)
    /// Raised elements on a surface (menus, unfilled progress blocks).
    static let surfaceRaised = Color(light: 0xEAE8E4, dark: 0x34322D)
    /// Hairline borders on cards and rows; doubles as the raised-key
    /// base-plate color (secondary/quiet keys).
    static let border = Color(light: 0xDDDBD7, dark: 0x3D3B35)
    /// Stronger borders (sheets, outlined buttons, chips); the base
    /// plate under primary keys.
    static let borderStrong = Color(light: 0xC2C0BA, dark: 0x4E4B43)

    static let textPrimary = Color(light: 0x232220, dark: 0xF0EDE6)
    static let textSecondary = Color(light: 0x6B6965, dark: 0x9D9B96)
    static let textFaint = Color(light: 0x767370, dark: 0x8A8781)

    /// The data green. Green is data, never chrome: deltas, net chips,
    /// "new" markers, next-due values, live progress, creation
    /// affordances (a future increment), and the ++ glyph.
    static let accent = Color(light: 0x17914B, dark: 0x46D17C)

    /// Completion purple (#201, Dave: "akin to a merged PR") — the
    /// third hue job: green is data in motion, blue is selection,
    /// purple is what's landed. GitHub's merged pair, familiar on sight.
    static let done = Color(light: 0x8250DF, dark: 0xA371F7)
    /// Committed timeline nodes on the Today rail — finished, so purple.
    static let committedFill = done

    /// Selected state ONLY (Quiet Arcade, v5 of the color notes):
    /// solid fill on toggled-on segments, active filter chips,
    /// schedule day circles, and toggle tint. Never an action fill,
    /// never a link/text color (those call sites became quiet keys).
    /// Chroma/lightness-matched to `accent` and `done` so the triad
    /// reads as siblings; white ≈ 5.2:1 on light, 0x161616 ≈ 7.4:1
    /// on dark.
    static let selected = Color(light: 0x1668D2, dark: 0x5CA8F5)
    /// Content on a SOLID selected fill. Never white on the
    /// dark-scheme blue.
    static let onSelected = Color(light: 0xFFFFFF, dark: 0x161616)
    /// The superset return-loop at REST (design handoff 2026-07-12 v2).
    /// An OPAQUE warm gray, a step more prominent than the neutral spine
    /// (`border`) but quieter than any blue. Must be opaque: a
    /// semi-transparent stroke (the first pass shipped `selected.opacity(0.5)`)
    /// composites with ITSELF wherever the Canvas sub-paths overlap — the
    /// quarter-curve/line joins and each chevron over the line — so those
    /// spots read darker. Opaque ink strokes uniformly regardless of draw
    /// order. Product decision this round: blue = the MOMENT of creating
    /// (selection field + snap line + spark); gray = the bound unit at rest.
    static let supersetLoop = Color(light: 0x7C786F, dark: 0x7C786F)

    /// Selected-state fill; always accompanied by `selectedRing`.
    static let selectedTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: 0x5CA8F5).withAlphaComponent(0.16)
            : UIColor(hex: 0x1668D2).withAlphaComponent(0.12)
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

    // MARK: - Motion

    /// The motion grammar as tunable tokens — the design law ("selection
    /// slides, data rolls, the app always feels fast") lived only in prose
    /// with `.easeOut(duration: 0.15)` copy-pasted ~30 times. Call sites
    /// reference these instead, so the tempo is consistent and dialable
    /// from one place. Deliberate flourishes (splash fade, superset landing
    /// bloom, the completion beat) keep their own longer curves inline —
    /// they are exceptions to the fast-feel rule, not part of it.
    enum Anim {
        /// Selection changes: the segmented pill sliding between segments,
        /// selected-state fills, active filter chips. A snappy spring reads
        /// crisp — velocity is front-loaded (immediate response to touch)
        /// and it settles without overshoot. Replaces `.easeOut(0.15)`,
        /// whose decelerating tail made a large sliding object crawl into
        /// place and read as muddy (Dave, 2026-07-12). One line to retune
        /// the whole app's selection feel.
        static let selection: Animation = .snappy(duration: 0.25, extraBounce: 0)
        /// The house curve for everything that isn't a selection slide or a
        /// deliberate flourish: data rolls (paired with `.numericText`),
        /// opacity fades, search expansion. The "~0.15 s ease-out" of the
        /// motion law.
        static let standard: Animation = .easeOut(duration: 0.15)
        /// RaisedKey cap depression — the fastest motion in the app.
        static let press: Animation = .easeOut(duration: 0.06)
    }
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
