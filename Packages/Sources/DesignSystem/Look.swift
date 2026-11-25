import SwiftUI

/// The person's two choices of how the app looks, the appearance and the theme, kept on the
/// device in `UserDefaults` and read as the app launches, so the first frame already shows them.
/// Each is stored as it changes. A stored theme id that names none reads as PlusPlus, and an
/// appearance that names none as `Appearance.initial`.
@Observable
public final class Look {
    public var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    public var theme: Theme {
        didSet { defaults.set(theme.id, forKey: Self.themeKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public static let appearanceKey = "appearance"
    public static let themeKey = "theme"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Self.appearanceKey).flatMap(Appearance.init)
            ?? .initial
        theme = Theme.stored(id: defaults.string(forKey: Self.themeKey))
    }

    /// What the window is held to (`Theme.colorScheme(for:)`).
    public var colorScheme: ColorScheme? {
        theme.colorScheme(for: appearance)
    }
}
