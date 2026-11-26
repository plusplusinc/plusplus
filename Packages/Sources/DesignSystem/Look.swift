import SwiftUI

/// The person's choice of how the app looks (`Appearance`), kept on the device in
/// `UserDefaults` and read as the app launches, so the first frame already shows it. It is
/// stored as it changes; a stored value that names none reads as `Appearance.initial`.
@Observable
public final class Look {
    public var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public static let appearanceKey = "appearance"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Self.appearanceKey).flatMap(Appearance.init)
            ?? .initial
    }
}
