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
    /// The pool's unit in the US, and the reason swimming needed a pace
    /// reference of its own: a 25-yard pool counts lengths, not meters.
    case yards = "yd"

    public var symbol: String { rawValue }

    public var displayName: String {
        switch self {
        case .meters: "meters"
        case .kilometers: "kilometers"
        case .miles: "miles"
        case .yards: "yards"
        }
    }

    /// Stepper increment for a distance value.
    public var step: Double {
        switch self {
        case .meters: 50
        case .kilometers: 0.25
        case .miles: 0.25
        // One length of a 25-yard pool, so a set reads in lengths.
        case .yards: 25
        }
    }

    /// Wheel granularity — finer than the stepper in meters so 25 m
    /// increments (a 425 m sled course) stay reachable.
    public var wheelStep: Double {
        switch self {
        case .meters: 25
        case .kilometers: 0.25
        case .miles: 0.25
        case .yards: 25
        }
    }

    public var range: ClosedRange<Double> {
        switch self {
        case .meters: 25...50000
        case .kilometers: 0.25...100
        case .miles: 0.25...100
        // A length at the bottom, an English Channel crossing at the top.
        case .yards: 25...40000
        }
    }

    /// Starting point when a distance is first set from empty: a 500 m erg
    /// piece, a 5 km run, a 3 mi run.
    public var defaultValue: Double {
        switch self {
        case .meters: 500
        case .kilometers: 5
        case .miles: 3
        // Twenty lengths of a short-course pool.
        case .yards: 500
        }
    }

    // MARK: - Pace
    //
    // The denominator itself lives in `PaceReference` now. A unit still
    // implies one, because it very nearly always names the sport too: an
    // erg thinks in meters and speaks /500m, a road run in miles and
    // speaks /mi, a pool in yards and speaks /100yd. What changed is that
    // the implication is now a DEFAULT rather than the whole story, so a
    // metric pool can say /100m without pretending to be an erg. A
    // `MetricProfile` carrying its own reference overrides these.

    /// The convention this unit implies when a profile states nothing.
    public var defaultPaceReference: PaceReference {
        switch self {
        case .meters: .per500Meters
        case .kilometers: .perKilometer
        case .miles: .perMile
        case .yards: .per100Yards
        }
    }

    /// "/500m", "/km", "/mi", "/100yd" — the suffix a pace value renders
    /// with, at this unit's own convention.
    public var paceLabel: String { defaultPaceReference.label }

    /// The reference distance, in meters, a pace is quoted over — the
    /// denominator that turns a live speed into a "per unit" split.
    public var paceReferenceMeters: Double { defaultPaceReference.meters }

    /// A raw meter distance expressed in this unit — for showing a live
    /// GPS distance ("1.24 mi", "1500 m") in the exercise's own
    /// denomination. Meters stay meters; the rest divide by their worth.
    public func value(fromMeters meters: Double) -> Double {
        self == .meters ? meters : meters / metersPerUnit
    }

    /// How many meters one unit is worth — the inverse of
    /// `value(fromMeters:)`, needed the moment anything has to relate a
    /// distance to a pace (whose reference is always in meters).
    public var metersPerUnit: Double {
        switch self {
        case .meters: 1
        case .kilometers: 1000
        case .miles: 1609.344
        case .yards: 0.9144
        }
    }

    /// A distance in this unit expressed in raw meters.
    public func meters(from value: Double) -> Double {
        value * metersPerUnit
    }

    public var paceRange: ClosedRange<Double> { defaultPaceReference.range }

    public var paceDefault: Double { defaultPaceReference.defaultValue }

    public var paceWheelStep: Double { defaultPaceReference.wheelStep }

    // MARK: - Speed
    // A treadmill's dial, denominated to match the distance unit. Meters
    // fall back to km/h — a meters-denominated exercise showing a speed
    // row is already an exotic combination.

    /// Yards rides with miles: both are US denominations, so a treadmill
    /// dial beside them reads in mph.
    private var usesImperialSpeed: Bool { self == .miles || self == .yards }

    public var speedLabel: String {
        usesImperialSpeed ? "mph" : "km/h"
    }

    public var speedRange: ClosedRange<Double> {
        usesImperialSpeed ? 0.5...15 : 1...25
    }

    public var speedDefault: Double {
        usesImperialSpeed ? 6 : 10
    }
}
