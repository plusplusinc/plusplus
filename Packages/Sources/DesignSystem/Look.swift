import SwiftUI

/// The person's choice of how the app looks, kept on the device in `UserDefaults` and read as
/// the app launches, so the first frame already shows it: the look chosen (`appearance`, light
/// or dark), whether it follows the phone instead (`isAutomatic`), and whether dark is true
/// black (`isVoid`). Each is stored as it changes. A stored look that names none reads as
/// `Appearance.initial`. Values stored by earlier builds read as the same choice: the four
/// appearances (light, dark, auto, black-belt) before the switches, and the Void switch
/// under its earlier key (`legacyVoidKey`).
@Observable
public final class Look {
    public var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    public var isAutomatic: Bool {
        didSet { defaults.set(isAutomatic, forKey: Self.automaticKey) }
    }

    /// Kept while its switch is hidden (Light held), so the switch comes back as it was.
    public var isVoid: Bool {
        didSet { defaults.set(isVoid, forKey: Self.voidKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    static let appearanceKey = "appearance"
    static let automaticKey = "appearance-automatic"
    static let voidKey = "void"
    /// Where earlier builds kept the Void switch.
    static let legacyVoidKey = "black-belt"
    /// Every key the look is stored under, for a reset.
    public static let keys = [appearanceKey, automaticKey, voidKey, legacyVoidKey]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.appearanceKey)
        var automatic = defaults.bool(forKey: Self.automaticKey)
        let hasLegacy = defaults.object(forKey: Self.legacyVoidKey) != nil
        var void = defaults.object(forKey: Self.voidKey) == nil
            ? defaults.bool(forKey: Self.legacyVoidKey)
            : defaults.bool(forKey: Self.voidKey)
        switch stored {
        case "auto":
            automatic = true
            appearance = .dark
        case "black-belt":
            void = true
            appearance = .dark
        default:
            appearance = stored.flatMap(Appearance.init(rawValue:)) ?? .initial
        }
        isAutomatic = automatic
        isVoid = void
        if (stored != nil && stored != appearance.rawValue) || hasLegacy {
            defaults.set(appearance.rawValue, forKey: Self.appearanceKey)
            defaults.set(automatic, forKey: Self.automaticKey)
            defaults.set(void, forKey: Self.voidKey)
            defaults.removeObject(forKey: Self.legacyVoidKey)
        }
    }

    /// What the window is held to: the look chosen, or nothing with Automatic on, so it follows
    /// the phone.
    public var colorScheme: ColorScheme? {
        isAutomatic ? nil : appearance.colorScheme
    }

    /// Whether the Void switch can do anything: the app can be dark, Dark held or
    /// Automatic on.
    public var offersVoid: Bool {
        isAutomatic || appearance == .dark
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
