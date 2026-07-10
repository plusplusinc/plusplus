import Foundation

/// What a distance-tracked exercise's numbers are denominated in. Same law
/// as WeightUnit: a declaration, never a conversion — 2000 stays 2000 when
/// the unit chip changes. Chosen per exercise (an erg thinks in meters, a
/// run in miles or kilometers), not per app, because both genuinely coexist
/// in one library.
public enum DistanceUnit: String, Codable, CaseIterable, Sendable {
    case meters = "m"
    case kilometers = "km"
    case miles = "mi"

    public var symbol: String { rawValue }

    public var displayName: String {
        switch self {
        case .meters: "meters"
        case .kilometers: "kilometers"
        case .miles: "miles"
        }
    }

    /// Stepper increment for a distance value.
    public var step: Double {
        switch self {
        case .meters: 50
        case .kilometers: 0.25
        case .miles: 0.25
        }
    }

    /// Wheel granularity — finer than the stepper in meters so 25 m
    /// increments (a 425 m sled course) stay reachable.
    public var wheelStep: Double {
        switch self {
        case .meters: 25
        case .kilometers: 0.25
        case .miles: 0.25
        }
    }

    public var range: ClosedRange<Double> {
        switch self {
        case .meters: 25...50000
        case .kilometers: 0.25...100
        case .miles: 0.25...100
        }
    }

    /// Starting point when a distance is first set from empty: a 500 m erg
    /// piece, a 5 km run, a 3 mi run.
    public var defaultValue: Double {
        switch self {
        case .meters: 500
        case .kilometers: 5
        case .miles: 3
        }
    }

    // MARK: - Pace
    // Pace is time over a reference distance, and the reference rides the
    // unit: meters mean an erg, and ergs speak splits per 500 m; miles and
    // kilometers pace per mile/km. Values are stored as plain seconds.

    /// "/500m", "/km", "/mi" — the suffix a pace value renders with.
    public var paceLabel: String {
        switch self {
        case .meters: "/500m"
        case .kilometers: "/km"
        case .miles: "/mi"
        }
    }

    public var paceRange: ClosedRange<Double> {
        switch self {
        case .meters: 60...300      // 1:00–5:00 per 500 m
        case .kilometers: 120...1200 // 2:00–20:00 per km
        case .miles: 180...1800      // 3:00–30:00 per mi
        }
    }

    /// 2:00 /500m, 6:00 /km, 10:00 /mi.
    public var paceDefault: Double {
        switch self {
        case .meters: 120
        case .kilometers: 360
        case .miles: 600
        }
    }

    /// Splits are dialed in single seconds on an erg; road paces in 5 s.
    public var paceWheelStep: Double {
        self == .meters ? 1 : 5
    }

    // MARK: - Speed
    // A treadmill's dial, denominated to match the distance unit. Meters
    // fall back to km/h — a meters-denominated exercise showing a speed
    // row is already an exotic combination.

    public var speedLabel: String {
        self == .miles ? "mph" : "km/h"
    }

    public var speedRange: ClosedRange<Double> {
        self == .miles ? 0.5...15 : 1...25
    }

    public var speedDefault: Double {
        self == .miles ? 6 : 10
    }
}
