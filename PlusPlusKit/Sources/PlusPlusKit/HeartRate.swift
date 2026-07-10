import Foundation

/// Heart-rate vocabulary shared by the app and the watch: the five-zone
/// model as fractions of max heart rate, an optional cardio target
/// (zone or explicit bpm range), and the pure math both platforms
/// resolve against. Platform-pure — HealthKit itself stays in the app
/// and watch targets; the Kit only speaks numbers.
public enum HeartRate {
    /// Age-based ceiling (220 − age), clamped to a sane band so a typo'd
    /// birthday can't produce zones nobody has.
    public static func estimatedMax(age: Int) -> Int {
        min(220, max(120, 220 - age))
    }

    /// When no age is readable: a mid-30s adult's estimate. Zones drawn
    /// from this are approximate — good enough for "roughly zone 2",
    /// which is all a target claims.
    public static let fallbackMax = 185
}

/// The common five-zone model. Bounds are fractions of max HR; zone 5
/// is open above (harder than max isn't a sixth zone).
public enum HeartRateZone: Int, Codable, CaseIterable, Identifiable, Sendable {
    case zone1 = 1, zone2, zone3, zone4, zone5

    public var id: Int { rawValue }

    public var label: String { "Zone \(rawValue)" }
    public var shortLabel: String { "Z\(rawValue)" }

    /// The word a coach would use — rendered as a caption beside the
    /// zone, never alone.
    public var descriptor: String {
        switch self {
        case .zone1: "easy"
        case .zone2: "steady"
        case .zone3: "tempo"
        case .zone4: "hard"
        case .zone5: "max"
        }
    }

    /// Lower fraction of max HR (inclusive).
    var lowerFraction: Double {
        switch self {
        case .zone1: 0.50
        case .zone2: 0.60
        case .zone3: 0.70
        case .zone4: 0.80
        case .zone5: 0.90
        }
    }

    /// Upper fraction (exclusive); nil for the open-ended zone 5.
    var upperFraction: Double? {
        switch self {
        case .zone1: 0.60
        case .zone2: 0.70
        case .zone3: 0.80
        case .zone4: 0.90
        case .zone5: nil
        }
    }

    /// Whole-bpm display bounds against a max HR. Zone 5's display
    /// upper is the max itself; membership above it still counts (see
    /// `HeartRateTarget.contains`).
    public func bpmRange(maxHeartRate: Int) -> ClosedRange<Int> {
        let lower = Int((lowerFraction * Double(maxHeartRate)).rounded())
        let upper = upperFraction.map { Int(($0 * Double(maxHeartRate)).rounded()) - 1 } ?? maxHeartRate
        return lower...max(lower, upper)
    }

    /// The zone a reading falls in; nil below zone 1 (resting isn't a
    /// training zone).
    public static func zone(for bpm: Int, maxHeartRate: Int) -> HeartRateZone? {
        guard maxHeartRate > 0 else { return nil }
        let fraction = Double(bpm) / Double(maxHeartRate)
        guard fraction >= 0.50 else { return nil }
        if fraction >= 0.90 { return .zone5 }
        return allCases.first { fraction >= $0.lowerFraction && fraction < ($0.upperFraction ?? .infinity) }
    }
}

/// An optional cardio prescription: a named zone or an explicit bpm
/// range. Guidance, never a logged metric — sets don't record heart
/// rate actuals; the session's summary does.
public enum HeartRateTarget: Equatable, Sendable {
    case zone(HeartRateZone)
    case range(lowerBPM: Int, upperBPM: Int)

    /// Resolved whole-bpm bounds. Zone targets need a max HR; explicit
    /// ranges are already bpm (bounds normalized so a swapped pair
    /// can't produce an empty range).
    public func bpmRange(maxHeartRate: Int) -> ClosedRange<Int> {
        switch self {
        case .zone(let zone):
            zone.bpmRange(maxHeartRate: maxHeartRate)
        case .range(let lower, let upper):
            min(lower, upper)...max(lower, upper)
        }
    }

    /// Whether a live reading satisfies the target. Zone 5 is open
    /// above — beyond max is not a miss.
    public func contains(_ bpm: Int, maxHeartRate: Int) -> Bool {
        let range = bpmRange(maxHeartRate: maxHeartRate)
        if case .zone(.zone5) = self {
            return bpm >= range.lowerBound
        }
        return range.contains(bpm)
    }

    /// "Z2 · 117–136" with a max HR to resolve against, "Zone 2" bare;
    /// explicit ranges are always "130–150 bpm".
    public func label(maxHeartRate: Int?) -> String {
        switch self {
        case .zone(let zone):
            guard let maxHeartRate else { return zone.label }
            let range = zone.bpmRange(maxHeartRate: maxHeartRate)
            return "\(zone.shortLabel) · \(range.lowerBound)–\(range.upperBound)"
        case .range(let lower, let upper):
            return "\(min(lower, upper))–\(max(lower, upper)) bpm"
        }
    }
}

extension HeartRateTarget: Codable {
    // Persisted (SwiftData JSON blobs, watch plan payloads), so the
    // encoding is explicit — {"kind":"zone","zone":2} /
    // {"kind":"range","lower":130,"upper":150} — never the synthesized
    // associated-value shape, which is a compiler implementation detail.
    private enum CodingKeys: String, CodingKey {
        case kind, zone, lower, upper
    }

    private enum Kind: String, Codable {
        case zone, range
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .zone:
            let raw = try container.decode(Int.self, forKey: .zone)
            guard let zone = HeartRateZone(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .zone, in: container,
                    debugDescription: "unknown heart-rate zone \(raw)"
                )
            }
            self = .zone(zone)
        case .range:
            self = .range(
                lowerBPM: try container.decode(Int.self, forKey: .lower),
                upperBPM: try container.decode(Int.self, forKey: .upper)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .zone(let zone):
            try container.encode(Kind.zone, forKey: .kind)
            try container.encode(zone.rawValue, forKey: .zone)
        case .range(let lower, let upper):
            try container.encode(Kind.range, forKey: .kind)
            try container.encode(lower, forKey: .lower)
            try container.encode(upper, forKey: .upper)
        }
    }
}
