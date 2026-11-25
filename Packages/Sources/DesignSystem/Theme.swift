import SwiftUI

/// A named set of colors the app can be drawn in: a value for every `ColorToken`, in a light
/// look, a dark look, or both. Which look shows is the appearance's (`colorScheme(for:)`), or the
/// only one there is.
///
/// PlusPlus's own values are the asset catalog's colorsets, Increase Contrast variants
/// included; every other theme's are worked out from a base16 palette (`Palette`).
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

    /// PlusPlus first, then the rest by name.
    public static let all: [Self] = [.plusPlus] + [.nord].sorted { $0.name < $1.name }

    /// The theme a stored id names, or PlusPlus for one that names none.
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
