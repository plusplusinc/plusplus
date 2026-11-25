import SwiftUI

/// A named set of colors the app can be drawn in: a value for every `ColorToken`, in a light
/// look, a dark look, or both. Which look shows is the appearance's (`colorScheme(for:)`), or the
/// only one there is.
///
/// PlusPlus's own values are the asset catalog's colorsets, Increase Contrast variants
/// included; every other theme's are worked out from its five colors (`Palette`, `Themes.swift`).
public nonisolated struct Theme: Identifiable, Sendable, Equatable {
    /// Stored as the person's choice (`Look`), so never changed once shipped.
    public let id: String
    public let name: String
    let looks: Looks

    enum Looks: Sendable {
        /// The asset catalog's colorsets, light and dark.
        case catalog
        case both(light: Palette, dark: Palette)
        case darkOnly(Palette)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    public static let plusPlus = Self(id: "plusplus", name: "PlusPlus", looks: .catalog)

    /// PlusPlus first, then the rest in their curated order (`ours`).
    public static let all: [Self] = [.plusPlus] + ours

    /// The color schemes this theme has a look for.
    public var schemes: [ColorScheme] {
        isDarkOnly ? [.dark] : [.light, .dark]
    }

    /// Whether a color reads as a red, which `accent` never is: it fills the + that adds an
    /// exercise, and a red + reads as a warning. A red is a color with OKLab chroma of at least
    /// 0.05 (not a gray) whose OKLab hue is from 350° round to 40°: from the pinks' edge to where
    /// orange begins. A pink-red and a coral (7° to 17°) and an orange that reads as rust (39°)
    /// fall inside; a peach (42°), a hot pink (347°), and Plum's orchid (338°) outside.
    public static func isRed(_ color: Color.Resolved) -> Bool {
        let lab = OKLab(RGB(color))
        let chroma = (lab.greenRed * lab.greenRed + lab.blueYellow * lab.blueYellow).squareRoot()
        var hue = atan2(lab.blueYellow, lab.greenRed) * 180 / .pi
        if hue < 0 {
            hue += 360
        }
        return chroma >= 0.05 && (hue >= 350 || hue < 40)
    }

    /// The theme a stored id names, or PlusPlus for one that names none, such as an id an
    /// earlier build stored for a theme since dropped (`nord`).
    public static func stored(id: String?) -> Self {
        all.first { $0.id == id } ?? .plusPlus
    }

    public var isDarkOnly: Bool {
        if case .darkOnly = looks {
            true
        } else {
            false
        }
    }

    /// What the window is held to: dark for a dark-only theme whatever the appearance; otherwise
    /// the appearance's, or nothing on Auto, so it follows the phone.
    public func colorScheme(for appearance: Appearance) -> ColorScheme? {
        if isDarkOnly {
            return .dark
        }
        switch appearance {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil
        }
    }

    /// The look this theme's card shows (`ThemeCard`), whichever theme the window is in: its
    /// only one, or the one the appearance calls for, the phone's on Auto. Under a dark-only
    /// theme with Light chosen, PlusPlus's card still shows its light look.
    public func shownScheme(for appearance: Appearance, phone: ColorScheme) -> ColorScheme {
        colorScheme(for: appearance) ?? phone
    }

    /// "Light and dark", or "Dark only".
    public var looksLine: String {
        isDarkOnly ? String(localized: "Dark only") : String(localized: "Light and dark")
    }

    func resolve(_ token: ColorToken, in environment: EnvironmentValues)
        -> Color.Resolved
    {
        switch looks {
        case .catalog:
            Color(token.rawValue, bundle: .module).resolve(in: environment)
        case let .both(light, dark):
            (environment.colorScheme == .dark ? dark : light)[token]
        case let .darkOnly(dark):
            dark[token]
        }
    }
}

/// How the app looks: held light, held dark, or following the phone.
public nonisolated enum Appearance: String, CaseIterable, Sendable {
    case light
    case dark
    case auto

    /// A new install, and a stored value that names none: dark, as the app was before the
    /// choice existed, until the light palette has had its review.
    public static let initial = Self.dark

    public var name: String {
        switch self {
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        case .auto: String(localized: "Auto")
        }
    }
}

nonisolated extension EnvironmentValues {
    /// The theme `Color.pp` draws in. A subtree set to another draws in that one.
    @Entry public var theme = Theme.plusPlus
}
