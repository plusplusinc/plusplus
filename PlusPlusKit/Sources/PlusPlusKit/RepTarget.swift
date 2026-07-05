import Foundation

/// A planned rep target: a single value ("10") or a range ("15–20"), as PT
/// and hypertrophy prescriptions are usually written. Pure value logic,
/// SwiftUI-free and unit tested; `WorkoutExercise` stores it as the
/// `reps`/`repsUpper` pair.
public struct RepTarget: Equatable, Sendable {
    public let lower: Int?
    /// Set only when this is a real range (upper > lower).
    public let upper: Int?

    public static let allowedReps = 1...100
    public static let defaultReps = 10

    public init(lower: Int?, upper: Int? = nil) {
        guard let lower else {
            self.lower = nil
            self.upper = nil
            return
        }
        let clampedLower = min(max(lower, Self.allowedReps.lowerBound), Self.allowedReps.upperBound)
        self.lower = clampedLower
        if let upper {
            let clampedUpper = min(upper, Self.allowedReps.upperBound)
            self.upper = clampedUpper > clampedLower ? clampedUpper : nil
        } else {
            self.upper = nil
        }
    }

    public var isRange: Bool { upper != nil }

    /// "—" when unset, "10" for a single target, "15–20" for a range.
    public var display: String {
        guard let lower else { return "—" }
        guard let upper else { return "\(lower)" }
        return "\(lower)–\(upper)"
    }

    /// Stepping shifts the whole range ("15–20" → "16–21") so the span the
    /// prescription asked for is preserved. From empty, lands on the default.
    public func incremented() -> RepTarget {
        guard let lower else { return RepTarget(lower: Self.defaultReps) }
        return RepTarget(lower: lower + 1, upper: upper.map { $0 + 1 })
    }

    public func decremented() -> RepTarget {
        guard let lower else { return RepTarget(lower: Self.defaultReps) }
        return RepTarget(lower: lower - 1, upper: upper.map { $0 - 1 })
    }
}
