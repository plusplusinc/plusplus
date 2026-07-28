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
    static let border = Color(light: 0xDDDBD7, dark: 0x3D3B35, lightHC: 0xB8B6B0, darkHC: 0x605D55)
    /// Stronger borders (sheets, outlined buttons, chips); the base
    /// plate under primary keys.
    static let borderStrong = Color(light: 0xC2C0BA, dark: 0x4E4B43, lightHC: 0x8F8D86, darkHC: 0x76736A)

    static let textPrimary = Color(light: 0x232220, dark: 0xF0EDE6)
    static let textSecondary = Color(light: 0x6B6965, dark: 0x9D9B96, lightHC: 0x565450, darkHC: 0xB8B6B0)
    /// The faintest text tier. Its original values (#767370 / #8A8781) read
    /// below WCAG 4.5:1 when placed on `surface`/card grounds (~4.2:1), where
    /// much of the caption copy actually sits — so both sides were darkened a
    /// half-step to clear the floor on surface while staying a visible tier
    /// below `textSecondary`. High-contrast variants push further. (a11y audit
    /// 2026-07-13.)
    static let textFaint = Color(light: 0x6F6C68, dark: 0x949089, lightHC: 0x4F4D49, darkHC: 0xBFBDB6)

    /// The data green. Green is data, never chrome: deltas, net chips,
    /// "new" markers, next-due values, live progress, creation
    /// affordances (a future increment), and the ++ glyph.
    ///
    /// ⚠️ The five brand HUES live in `BrandPalette` (PlusPlusShared) so the
    /// widget extension reads the same values, HC variants included, instead
    /// of restating them (2026-07-28). The neutrals below stay here: widgets
    /// draw on the system's ground, not the app's paper.
    static let accent = BrandPalette.accent

    /// Completion purple (#201, Dave: "akin to a merged PR") — the
    /// third hue job: green is data in motion, blue is selection,
    /// purple is what's landed. GitHub's merged pair, familiar on sight.
    static let done = BrandPalette.done

    /// Selected state ONLY (Quiet Arcade, v5 of the color notes):
    /// solid fill on toggled-on segments, active filter chips,
    /// schedule day circles, and toggle tint. Never an action fill,
    /// never a link/text color (those call sites became quiet keys).
    /// Chroma/lightness-matched to `accent` and `done` so the triad
    /// reads as siblings; white ≈ 5.2:1 on light, 0x161616 ≈ 7.4:1
    /// on dark.
    static let selected = BrandPalette.selected
    /// Content on a SOLID selected fill. Never white on the
    /// dark-scheme blue. Few callers left since solid selection fills were
    /// retired (2026-07-28) — most selected content now takes `selectedInk`.
    static let onSelected = BrandPalette.onSelected
    /// Text and glyphs sitting on a `selectedTint` ground — the selected
    /// chip label, the day circle's letter, a checkmark in a selected row.
    /// ⚠️ NOT `selected`: that measures 4.07:1 on its own tint over `surface`
    /// in light mode, below the AA floor for the footnote-sized labels that
    /// carry it. See BrandPalette.
    static let selectedInk = BrandPalette.selectedInk
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
    /// The create-animation's pulse spark + chevron flare — a light blue
    /// brighter than `selected`, so the travelling glow reads as energy on
    /// top of the creation blue. Same tone both schemes (it's additive
    /// light, not a surface). Used only during the superset landing.
    static let supersetFlare = Color(light: 0x96C8FA, dark: 0x96C8FA)

    /// Selected-state fill; always accompanied by `selectedRing`. Reads its
    /// hex from `BrandPalette` rather than restating it — a per-scheme ALPHA
    /// is the one thing the shared `Color(light:dark:)` pair can't express,
    /// which is why this is built by hand rather than living there.
    static let selectedTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: BrandPalette.selectedDark).withAlphaComponent(0.16)
            : UIColor(hex: BrandPalette.selectedLight).withAlphaComponent(0.12)
    })
    /// 1 pt border accompanying every selectedTint fill. 0.55 → 0.7 in the
    /// 2026-07-13 audit, → 0.8 on 2026-07-28: 0.7 measured 2.89:1 against
    /// `surface` in light mode, just under the 3:1 UI-component floor, and
    /// the ring carries more weight now that it outlines a tint rather than
    /// edging a solid fill. 0.8 gives 3.43:1 light / 4.26:1 dark.
    static let selectedRing = selected.opacity(0.8)

    /// Filled controls — Start/Continue/Log set, Done capsules, setup
    /// CTAs: ink in light, cream in dark. Actions, never selection.
    static let primaryFill = Color(light: 0x232220, dark: 0xF0EDE6)
    /// Text and glyphs sitting on primaryFill.
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x161616)

    /// Exercise/routine notes ("form cues" amber).
    static let notes = BrandPalette.notes

    static let destructive = BrandPalette.destructive

    /// Swipe-block fills. ⚠️ NOT `accent`/`destructive`: a block is its own
    /// surface under a WHITE label the system owns, so the fill is chosen for
    /// that and fixed in both schemes. See BrandPalette — white on the
    /// dark-scheme green measured 1.97:1 before this.
    static let swipeAdd = BrandPalette.swipeAdd
    static let swipeDelete = BrandPalette.swipeDelete
    /// Curation turned off — UNFAV, REMOVE from kit.
    static let swipeNeutral = BrandPalette.swipeNeutral

    // MARK: - Metrics

    static let cardRadius: CGFloat = 14
    static let sheetRadius: CGFloat = 20
    static let controlRadius: CGFloat = 10
    /// The interactive-key radius (2026-07-19 "rounded squares everywhere"):
    /// RaisedKey caps, header icon keys, filter chips, the search field.
    /// It was the app's most-repeated radius yet lived as a bare literal at
    /// ~40 call sites until the 2026-07-23 design-review sweep named it.
    /// `FilterChipShape.cornerRadius` aliases this so chip call sites keep
    /// reading in chip vocabulary.
    static let keyRadius: CGFloat = 11

    // MARK: - Motion

    /// The motion grammar as tunable tokens — the design law ("selection
    /// slides, data rolls, the app always feels fast") lived only in prose
    /// with `.easeOut(duration: 0.15)` copy-pasted ~30 times. Call sites
    /// reference these instead, so the tempo is consistent and dialable
    /// from one place. Deliberate flourishes (splash fade, superset landing
    /// bloom, the completion beat) keep their own longer curves inline —
    /// they are exceptions to the fast-feel rule, not part of it.
    enum Anim {
        /// True when the user has asked the system to minimize motion
        /// (Settings → Accessibility → Motion → Reduce Motion). Read at use
        /// time so the tokens below and every deliberate flourish quiet their
        /// large / spring / positional motion (WCAG 2.3.3). SwiftUI views
        /// should prefer `@Environment(\.accessibilityReduceMotion)`; this
        /// mirror exists for the token accessors and non-View call sites
        /// (e.g. `RevealController`).
        @MainActor static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

        /// Full-motion values, used when Reduce Motion is off.
        static let selectionFull: Animation = .snappy(duration: 0.25, extraBounce: 0)
        static let standardFull: Animation = .easeOut(duration: 0.15)

        /// Selection changes: the segmented pill sliding between segments,
        /// selected-state fills, active filter chips. A snappy spring reads
        /// crisp — velocity is front-loaded (immediate response to touch)
        /// and it settles without overshoot. Under Reduce Motion the sliding
        /// pill snaps in place instead of travelling.
        @MainActor static var selection: Animation { reduceMotion ? .linear(duration: 0.01) : selectionFull }
        /// The house curve for everything that isn't a selection slide or a
        /// deliberate flourish: data rolls (paired with `.numericText`),
        /// opacity fades, search expansion. Fades are fine under Reduce
        /// Motion; the token still resolves near-instant there for parity.
        @MainActor static var standard: Animation { reduceMotion ? .linear(duration: 0.01) : standardFull }
        /// RaisedKey cap depression — the fastest motion in the app; a 3–4 pt
        /// press is not vestibular motion, so it is unaffected by Reduce Motion.
        static let press: Animation = .easeOut(duration: 0.06)

        /// Resolve a deliberate large-motion flourish (whole-app reveal slide,
        /// card zoom, superset landing, the +1 pop): the full animation
        /// normally, `nil` (instant, no travel) under Reduce Motion. Use at
        /// imperative `withAnimation` sites.
        @MainActor static func flourish(_ full: Animation) -> Animation? { reduceMotion ? nil : full }
    }
}
