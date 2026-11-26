import SwiftUI

/// The person's choice of how the app looks, kept on the device in `UserDefaults` and read as
/// the app launches, so the first frame already shows it: the look chosen (`appearance`, light
/// or dark), whether it follows the phone instead (`isAutomatic`), and whether dark is true
/// black (`isBlackBelt`). Each is stored as it changes. A stored look that names none reads as
/// `Appearance.initial`; the four appearances stored before the switches (light, dark, auto,
/// black-belt) read as the same choice in the three.
@Observable
public final class Look {
    public var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    public var isAutomatic: Bool {
        didSet { defaults.set(isAutomatic, forKey: Self.automaticKey) }
    }

    public var isBlackBelt: Bool {
        didSet { defaults.set(isBlackBelt, forKey: Self.blackBeltKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public static let appearanceKey = "appearance"
    public static let automaticKey = "appearance-automatic"
    public static let blackBeltKey = "black-belt"
    public static let keys = [appearanceKey, automaticKey, blackBeltKey]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.appearanceKey)
        var automatic = defaults.bool(forKey: Self.automaticKey)
        var blackBelt = defaults.bool(forKey: Self.blackBeltKey)
        switch stored {
        case "auto":
            automatic = true
            appearance = .dark
        case "black-belt":
            blackBelt = true
            appearance = .dark
        default:
            appearance = stored.flatMap(Appearance.init(rawValue:)) ?? .initial
        }
        isAutomatic = automatic
        isBlackBelt = blackBelt
        if stored != appearance.rawValue, stored != nil {
            defaults.set(appearance.rawValue, forKey: Self.appearanceKey)
            defaults.set(automatic, forKey: Self.automaticKey)
            defaults.set(blackBelt, forKey: Self.blackBeltKey)
        }
    }

    /// What the window is held to: the look chosen, or nothing with Automatic on, so it follows
    /// the phone.
    public var colorScheme: ColorScheme? {
        isAutomatic ? nil : appearance.colorScheme
    }

    /// The look in effect, given the phone's own (nil before it is read).
    public func shown(phone: ColorScheme?) -> Appearance {
        guard isAutomatic else { return appearance }
        return phone.map(Appearance.init) ?? appearance
    }

    /// A picture's tap: that look, held, as iOS's own pictures turn Automatic off.
    public func choose(_ chosen: Appearance) {
        appearance = chosen
        isAutomatic = false
    }

    /// Automatic's switch. Turned off, the look in effect stays, as iOS's does.
    public func setAutomatic(_ isOn: Bool, phone: ColorScheme?) {
        if !isOn {
            appearance = shown(phone: phone)
        }
        isAutomatic = isOn
    }
}
