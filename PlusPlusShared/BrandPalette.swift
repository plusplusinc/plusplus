import SwiftUI
import UIKit

/// The brand hues, in ONE place, compiled into both the app and the widget
/// extension (2026-07-28, the colour audit).
///
/// They used to be restated in raw hex in three files — `Theme`, the widget
/// extension's `WTheme`, and `WatchTheme`. All three agreed when the audit
/// diffed them, and nothing kept them agreeing. One cost was already live:
/// `WTheme` carried no high-contrast variants, so the widgets silently
/// ignored Increase Contrast while the app honoured it. Reading them from
/// here fixes that by construction — a widget cannot get a hue right and its
/// HC pair wrong, because it no longer states either.
///
/// ⚠️ `WatchTheme` deliberately stays its own file: watchOS keeps the system's
/// black canvas and only ever renders the dark side, so it is a genuinely
/// different palette rather than a copy of this one. It is also a separate
/// target that does NOT compile PlusPlusShared.
///
/// Neutrals (paper, ink, borders) stay in `Theme`: the widget extension draws
/// on the system's widget ground, not the app's warm charcoal, so it has no
/// use for them and sharing them would imply a canvas it doesn't have.
enum BrandPalette {
    // MARK: Raw values
    // Named so a call site that genuinely needs ONE side (an always-dark
    // surface) can say so, instead of hand-writing the hex again.

    static let accentLight: UInt32 = 0x17914B
    static let accentDark: UInt32 = 0x46D17C
    static let doneLight: UInt32 = 0x8250DF
    static let doneDark: UInt32 = 0xA371F7
    static let selectedLight: UInt32 = 0x1668D2
    static let selectedDark: UInt32 = 0x5CA8F5

    // MARK: The hue jobs

    /// Data green: deltas, live progress, creation, the ++ glyph. Never chrome.
    static let accent = Color(light: accentLight, dark: accentDark, lightHC: 0x0E7A3D, darkHC: 0x67DD95)
    /// Completion purple — what has landed (GitHub's merged pair).
    static let done = Color(light: doneLight, dark: doneDark)
    /// Selection blue — the RING and any solid selected surface. Never an
    /// action fill, never a link colour. HC variants added 2026-07-28: with
    /// selection now reading as a tint rather than a solid fill, Increase
    /// Contrast has real work to do here.
    static let selected = Color(light: selectedLight, dark: selectedDark, lightHC: 0x0E4FA3, darkHC: 0x8CC4FA)
    /// The selection hue as TEXT ON A TINTED GROUND — a selected chip's label,
    /// a day circle's letter, a checkmark inside a `selectedTint` row.
    ///
    /// ⚠️ It exists because `selected` itself does NOT clear WCAG AA there
    /// (2026-07-28). On a 12% wash over `surface` the plain blue measures
    /// 4.07:1 against its own ground in light mode — under the 4.5:1 floor for
    /// normal text, and the chip labels are footnote/semibold, which is not
    /// large text. The solid fill it replaced measured 5.32:1, so the new
    /// treatment needed its own ink rather than reusing the fill colour.
    /// These land at ~6:1 on the worst ground, ~9:1 with Increase Contrast.
    static let selectedInk = Color(light: 0x0E4FA3, dark: 0x8CC4FA, lightHC: 0x08356E, darkHC: 0xB4DAFC)
    /// Content sitting ON a solid selection fill. Never white on the dark blue.
    static let onSelected = Color(light: 0xFFFFFF, dark: 0x161616)
    /// Advisory amber (form cues, "needs X", carried-over days). Never alarm.
    /// ⚠️ The light value darkened a half-step on 2026-07-28 (0x9A6700 →
    /// 0x8F5F00): the old one measured 4.39:1 on `surface`, and most amber
    /// copy sits on a card rather than the page. 4.98:1 now. Same remedy, and
    /// the same reason, as the `textFaint` darkening in the 2026-07-13 audit.
    static let notes = Color(light: 0x8F5F00, dark: 0xCFA14A, lightHC: 0x805400, darkHC: 0xDCB25E)
    /// Advisory amber as TEXT ON ITS OWN WASH — the "needs barbell" chip, the
    /// GPS-off key, a carried-over caption inside its amber card.
    ///
    /// ⚠️ Exactly the `selectedInk` story, one hue over (2026-07-28): plain
    /// `notes` on a 14% amber ground measures 4.13:1 in light mode, under the
    /// AA floor. These land at ~4.9 / ~5.7. Amber's wash and ring are tokens
    /// now (`Theme.notesWash`/`notesRing`) rather than five hand-built copies,
    /// which is what let this be measured once instead of five times.
    static let notesInk = Color(light: 0x805400, dark: 0xDCB25E, lightHC: 0x6E4800, darkHC: 0xE3BE72)
    static let destructive = Color(light: 0xCF222E, dark: 0xE5534B, lightHC: 0xB01722, darkHC: 0xEC6B63)

    // MARK: Ledger movement inks (2026-07-30)
    //
    // The target column's moved tokens: an ask for MORE wears the data
    // green, an ask for LESS a gentle brick (Dave: "decrease is not a
    // problem" — a planned deload is a choice, and the alarm red would make
    // every one read as an error). Both are caption-mono TEXT on
    // `background`/`surface`, so both clear 4.5:1 there.

    /// The accent hue as caption TEXT — taken at accent's high-contrast
    /// light value, because plain `accentLight` measures 3.65:1 on light
    /// `surface`, under the AA floor at caption size. The `selectedInk`
    /// story, third verse: a hue proven as a fill or a large glyph has not
    /// been shown to read as small text.
    static let increaseInk = Color(light: 0x0E7A3D, dark: 0x46D17C, lightHC: 0x0B6332, darkHC: 0x67DD95)
    /// The gentle brick for an ask below last time. Visibly NOT
    /// `destructive`: desaturated a long step, and never used on an action.
    /// 5.2:1 on light `surface`, 5.9:1 on dark.
    static let decreaseInk = Color(light: 0x9E4E44, dark: 0xE09084, lightHC: 0x873C33, darkHC: 0xEEB0A5)

    // MARK: Swipe blocks
    //
    // ⚠️ A swipe action block is ITS OWN SURFACE carrying a WHITE label, and
    // the label colour is the system's to choose — `.swipeActions` draws
    // titles white whatever the tint. So these fills are picked to carry white
    // at 4.5:1, and they are FIXED in both schemes rather than adaptive: the
    // dark-scheme text hues are bright by design, and white on the dark green
    // measured 1.97:1, white on the dark red 3.70:1 (2026-07-28 audit). Both
    // were pre-existing. Do NOT pass `accent`/`destructive` to a swipe tint.

    /// Additive curation — FAV, ADD to kit. White reads 5.43:1.
    static let swipeAdd = Color(hex: 0x0E7A3D)
    /// Destruction — DELETE. White reads 5.36:1.
    static let swipeDelete = Color(hex: 0xCF222E)
    /// Curation turned OFF — UNFAV, REMOVE from kit. Quieter in hue than
    /// `swipeDelete`, no worse in legibility: white reads 6.65:1.
    static let swipeNeutral = Color(hex: 0x5F5C58)

    /// The data green for surfaces that are ALWAYS dark whatever the device is
    /// set to — the Dynamic Island. Deliberately not adaptive: resolving by
    /// colour scheme there would paint the light-mode green on a black pill.
    static let accentOnDark = Color(hex: accentDark)
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
    /// works everywhere Color does, including Canvas drawing. Optional
    /// `lightHC`/`darkHC` supply stronger values used when the system
    /// Increase Contrast setting is on (`traits.accessibilityContrast ==
    /// .high`); omit them to reuse the standard value. This is the single
    /// hook through which the palette honors Increase Contrast (a11y audit
    /// 2026-07-13) — which is exactly why it lives here now, where the
    /// widget extension can reach it too.
    init(light: UInt32, dark: UInt32, lightHC: UInt32? = nil, darkHC: UInt32? = nil) {
        self.init(uiColor: UIColor { traits in
            let increased = traits.accessibilityContrast == .high
            switch traits.userInterfaceStyle {
            case .dark:
                return UIColor(hex: increased ? (darkHC ?? dark) : dark)
            default:
                return UIColor(hex: increased ? (lightHC ?? light) : light)
            }
        })
    }
}

/// ⚠️ Internal, not file-private: `Theme.selectedTint` builds a per-scheme
/// ALPHA, which the `Color` initializers above can't express, so it reaches
/// for this directly from Theme.swift. It was private while both lived in one
/// file.
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
