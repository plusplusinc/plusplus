import Foundation

// How the current exercise of a workout reads: which set it is on, and its plan's numbers, each
// with what it counts, shown large.

/// One of the current exercise's numbers, with what it counts: "10" "reps", "35" "lb/side",
/// "2:30" "min".
public struct PlanFigure: Hashable, Sendable {
    public let number: String
    public let unit: String
}

extension RoutineExercise {
    /// "Set 1 of 3", or "Round 1 of 3" in a superset, whose rows share one round count. A side
    /// reads apart (`Side.text`), so the view can set it off.
    public func progressText(set: Int, inSuperset: Bool, locale: Locale = .current) -> String {
        let set = set.formatted(.number.locale(locale))
        let sets = plan.sets.formatted(.number.locale(locale))
        return "\(inSuperset ? "Round" : "Set") \(set) of \(sets)"
    }

    /// The reps or time, then the weight if the exercise holds one, each saying what it is for
    /// as the row does: "10" "reps per side", "20" "lb/side". With a `side` named, the set is
    /// that side's alone, so the reps or time drop "per side": "10" "reps".
    public func figures(side: Side? = nil, locale: Locale = .current) -> [PlanFigure] {
        let target = plan.target.figure(locale: locale)
        let unit = side == nil ? qualified(target.unit, .target) : target.unit
        var figures = [PlanFigure(number: target.number, unit: unit)]
        if let weight = shownWeight {
            figures.append(PlanFigure(
                number: weight.number(locale: locale),
                unit: qualified(weight.unit.rawValue, .weight),
            ))
        }
        return figures
    }

    /// The figures in words, for VoiceOver: "10 reps per side, 50 pounds"; with a `side`,
    /// "10 reps, 50 pounds".
    public func spokenFigures(side: Side? = nil, locale: Locale = .current) -> String {
        var parts = [side == nil ? spokenValue(of: .target, locale: locale)
            : plan.target.spokenText(locale: locale)]
        if shownWeight != nil {
            parts.append(spokenValue(of: .weight, locale: locale))
        }
        return parts.joined(separator: ", ")
    }
}

extension Side {
    /// "Left", "Right": the side a set of a per-side exercise works.
    public var text: String {
        switch self {
        case .left: String(localized: "Left")
        case .right: String(localized: "Right")
        }
    }
}

/// How far through its sets a row is, in words, for VoiceOver: "2 of 3 sets done".
public func spokenProgress(done: Int, total: Int, locale: Locale = .current) -> String {
    let done = done.formatted(.number.locale(locale))
    return "\(done) of \(counted(total, "set", "sets", locale: locale)) done"
}

extension SetTarget {
    /// The number and its unit apart: "10" "reps", "30" "s", "2:30" "min".
    func figure(locale: Locale) -> (number: String, unit: String) {
        switch self {
        case let .reps(reps):
            (reps.formatted(.number.locale(locale)), reps == 1 ? "rep" : "reps")
        case let .time(seconds):
            TimeText.parts(seconds: seconds, locale: locale)
        }
    }
}
