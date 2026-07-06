import Foundation
import PlusPlusKit

/// One source of truth for the weight-unit setting's storage key
/// (issue #33). Views read it reactively via
/// `@AppStorage(WeightUnitSetting.key)`.
///
/// Toggling the unit never converts stored numbers — 225 stays 225 and
/// only the label, stepping, and defaults change. Values are
/// unit-agnostic by decree; the setting (and a bundle's `units` field)
/// declares what they mean.
enum WeightUnitSetting {
    static let key = "weightUnit"

    static var current: WeightUnit {
        WeightUnit(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .lb
    }
}
