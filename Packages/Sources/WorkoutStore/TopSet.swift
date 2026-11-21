import Foundation

/// An exercise's best round in one workout: the heaviest, and among those at that weight, the
/// most reps or the longest time. No weight orders as zero, so bodyweight to weighted is a gain.
public struct TopSet: Equatable, Sendable {
    public let target: SetTarget
    public let weight: Weight?

    public init(target: SetTarget, weight: Weight?) {
        self.target = target
        self.weight = weight
    }

    /// The weight in kilograms, so two units compare; zero for none.
    var kilograms: Double {
        guard let weight else { return 0 }
        return weight.unit == .kilograms ? weight.amount : weight.amount * Self.kilogramsPerPound
    }

    static let kilogramsPerPound = 0.45359237

    static func isBelow(_ one: Self, _ other: Self) -> Bool {
        let (oneWeight, otherWeight) = (one.kilograms, other.kilograms)
        if abs(oneWeight - otherWeight) > Self.sameWeight {
            return oneWeight < otherWeight
        }
        return one.target.amount < other.target.amount
    }

    /// Two weights closer than this are the same: a unit's conversion never lands exactly.
    static let sameWeight = 0.001

    /// How `self` compares with `earlier`, the same exercise's top set in a workout before;
    /// `.first` with none. Weight decides and the reps or time break a tie, so 8 × 135 lb to
    /// 5 × 150 lb is up 15 lb. One in reps against one in time, after a Customize, is `.changed`.
    public func change(from earlier: Self?) -> Change {
        guard let earlier else { return .first }
        guard earlier.target.isTime == target.isTime else { return .changed }
        let difference = kilograms - earlier.kilograms
        if abs(difference) > Self.sameWeight {
            // In the later set's unit, or the earlier's when the later has none.
            let unit = weight?.unit ?? earlier.weight?.unit ?? .pounds
            let amount = abs(unit == .kilograms ? difference : difference / Self.kilogramsPerPound)
            let gain = Gain.weight(Weight((amount * 100).rounded() / 100, unit))
            return difference > 0 ? .up(gain) : .down(gain)
        }
        let amount = target.amount - earlier.target.amount
        guard amount != 0 else { return .same }
        let gain: Gain = target.isTime
            ? .seconds(abs(amount))
            : .reps(abs(amount), withWeight: weight != nil)
        return amount > 0 ? .up(gain) : .down(gain)
    }
}

/// A top set against an earlier one.
public enum Change: Equatable, Sendable {
    /// No earlier one.
    case first
    case up(Gain)
    case same
    case down(Gain)
    /// One in reps and the other in time; shows nothing.
    case changed

    public var isUp: Bool {
        if case .up = self {
            true
        } else {
            false
        }
    }
}

/// How much a top set moved: a weight, reps, or seconds.
public enum Gain: Equatable, Sendable {
    case weight(Weight)
    /// `withWeight` when the set also carries a weight, so the figure says "reps" and can't be
    /// read as pounds.
    case reps(Int, withWeight: Bool)
    case seconds(Int)
}
