import Foundation

/// The unit weight numbers are denominated in. Stored values are plain
/// numbers — this declares what they mean (in the app's setting and in a
/// bundle's `units` field). Switching units never converts stored values;
/// 225 stays 225 and only the label and stepping change. Absent always
/// means pounds, so every pre-units file stays valid.
public enum WeightUnit: String, Codable, Sendable, CaseIterable {
    case lb
    case kg

    public var symbol: String {
        rawValue
    }

    /// Stepper increment — the smallest plate pair you'd add in practice.
    public var step: Double {
        switch self {
        case .lb: 5
        case .kg: 2.5
        }
    }

    /// Wheel granularity — microplates stay reachable.
    public var wheelStep: Double {
        switch self {
        case .lb: 2.5
        case .kg: 1.25
        }
    }

    /// Starting point when a weight is first set from empty: the empty
    /// bar (45 lb / 20 kg).
    public var defaultValue: Double {
        switch self {
        case .lb: 45
        case .kg: 20
        }
    }
}
