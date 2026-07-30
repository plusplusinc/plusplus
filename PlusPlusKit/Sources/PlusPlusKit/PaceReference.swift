import Foundation

/// What a pace is quoted OVER — the denominator, split out from the
/// distance unit that used to imply it.
///
/// `DistanceUnit` baked this in: meters meant `/500m`, because the only
/// meters-denominated exercise in the app was an erg and ergs speak
/// splits per five hundred. That held until swimming, where a metric
/// pool is also denominated in meters and speaks `/100m`. One unit, two
/// conventions, and no way to say which — which is why swimming was
/// unexpressible rather than merely missing.
///
/// The reference is now a value in its own right, and a `MetricProfile`
/// may carry one. Absent, it resolves to the unit's own convention, so
/// every profile written before this reads exactly as it did.
public enum PaceReference: String, Codable, CaseIterable, Sendable {
    case per100Meters = "100m"
    case per500Meters = "500m"
    case perKilometer = "km"
    case per100Yards = "100yd"
    case perMile = "mi"

    /// The denominator in meters — what turns a speed into a split.
    public var meters: Double {
        switch self {
        case .per100Meters: 100
        case .per500Meters: 500
        case .perKilometer: 1000
        case .per100Yards: 91.44
        case .perMile: 1609.344
        }
    }

    /// The suffix a pace value renders with.
    public var label: String {
        switch self {
        case .per100Meters: "/100m"
        case .per500Meters: "/500m"
        case .perKilometer: "/km"
        case .per100Yards: "/100yd"
        case .perMile: "/mi"
        }
    }

    /// Dialable bounds, in seconds. Wide enough for a walk at the slow end
    /// of each scale and a sprint at the fast one.
    public var range: ClosedRange<Double> {
        switch self {
        case .per100Meters, .per100Yards: 40...400   // 0:40–6:40 per 100
        case .per500Meters: 60...300                 // 1:00–5:00 per 500 m
        case .perKilometer: 120...1200               // 2:00–20:00 per km
        case .perMile: 180...1800                    // 3:00–30:00 per mi
        }
    }

    /// Where a pace lands when first set from empty.
    public var defaultValue: Double {
        switch self {
        case .per100Meters, .per100Yards: 120        // 2:00 per 100
        case .per500Meters: 120                      // 2:00 /500m
        case .perKilometer: 360                      // 6:00 /km
        case .perMile: 600                           // 10:00 /mi
        }
    }

    /// Short references are dialed in single seconds — a swimmer and a
    /// rower both care about one. Road paces move in fives.
    public var wheelStep: Double {
        switch self {
        case .per100Meters, .per500Meters, .per100Yards: 1
        case .perKilometer, .perMile: 5
        }
    }
}
