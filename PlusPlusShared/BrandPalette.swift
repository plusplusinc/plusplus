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
    /// Selection blue. Never an action fill, never a link colour.
    static let selected = Color(light: selectedLight, dark: selectedDark)
    /// Content sitting ON a solid selection fill. Never white on the dark blue.
    static let onSelected = Color(light: 0xFFFFFF, dark: 0x161616)
    /// Advisory amber (form cues, "needs X", carried-over days). Never alarm.
    static let notes = Color(light: 0x9A6700, dark: 0xCFA14A, lightHC: 0x805400, darkHC: 0xDCB25E)
    static let destructive = Color(light: 0xCF222E, dark: 0xE5534B, lightHC: 0xB01722, darkHC: 0xEC6B63)

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
