import Foundation

// How the current exercise of a workout reads: which set it is on, and its plan's numbers, each
// with what it counts, shown large.

/// One of the current exercise's numbers, with what it counts: "10" "reps", "35" "lb/side";
/// a time carries its units in its number, "1m 35s", and nothing or "per side" after it.
public struct PlanFigure: Hashable, Sendable {
    public let number: String
    public let unit: String
}

extension WorkoutExercise {
    /// The word that names where the current exercise is, "Set 1 of 3": "Set", or "Round" in a
    /// superset, whose rows share one round count. A side reads apart (`Side.text`), so the view
    /// can set it off.
    public static func progressWord(inSuperset: Bool) -> String {
        inSuperset ? "Round" : "Set"
    }

    /// The reps or time, then the weight if the exercise holds one, each saying what it is for
    /// as the row does: "10" "reps per side", "20" "lb/side". With a `side` named, the set is
    /// that side's alone, so the reps or time drop "per side": "10" "reps".
    public func figures(side: Side? = nil, locale: Locale = .current) -> [PlanFigure] {
        let target = plan.target.figure(locale: locale)
        let unit = side == nil
            ? qualified(target.unit, .target).trimmingCharacters(in: .whitespaces)
            : target.unit
        var figures = [PlanFigure(number: target.number, unit: unit)]
        if let weight = shownWeight {
            figures.append(PlanFigure(
                number: weight.number(locale: locale),
                unit: qualified(weight.unit.rawValue, .weight),
            ))
        }
        return figures
    }

    /// The figures as the current exercise shows them, on the phone and the Watch, each number
    /// over what it counts: a time under a minute as its seconds over "seconds", "30" "seconds";
    /// a minute or more as a clock over "min", "1:30" "min", which a plural unit misread as
    /// "1:00 minutes"; with "per side" after it where the plan's figure has it, so it reads as
    /// reps and weight do.
    public func shownFigures(side: Side?, locale: Locale = .current) -> [PlanFigure] {
        figures(side: side, locale: locale).enumerated().map { index, figure in
            guard index == 0, case let .time(seconds) = plan.target else { return figure }
            let number = seconds < 60
                ? seconds.formatted(.number.locale(locale))
                : Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond).locale(locale))
            let unit = seconds < 60 ? String(localized: "seconds") : String(localized: "min")
            return PlanFigure(
                number: number,
                unit: [unit, figure.unit].filter { !$0.isEmpty }.joined(separator: " "),
            )
        }
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
    /// The number and its unit apart: "10" "reps"; a time whole, "1m 35s" "".
    func figure(locale: Locale) -> (number: String, unit: String) {
        switch self {
        case let .reps(reps):
            (reps.formatted(.number.locale(locale)), reps == 1 ? "rep" : "reps")
        case let .time(seconds):
            (TimeText.text(seconds: seconds, locale: locale), "")
        }
    }
}
