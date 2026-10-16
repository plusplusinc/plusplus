import Foundation

// How a plan reads: on its row, and to VoiceOver. Every number carries its unit
// but the sets count, joined by a no-break space so a line never breaks between them, and says
// whether it's per side or each.

private let noBreakSpace = "\u{00A0}"

extension RoutineExercise {
    /// The row's detail line in parts: the plan, then the weight if it holds one.
    /// "3 × 10 reps per side", "50 lb".
    public func detailParts(locale: Locale = .current) -> [String] {
        let sets = plan.sets.formatted(.number.locale(locale))
        return line(
            amount: plan.target.text(locale: locale),
            sets: "\(sets)\(noBreakSpace)×\(noBreakSpace)",
            weight: shownWeight?.text(locale: locale),
        )
    }

    /// The detail line in words, for VoiceOver: "3 sets of 10 reps per side, 50 pounds".
    public func spokenDetail(locale: Locale = .current) -> String {
        let sets = plan.sets.formatted(.number.locale(locale))
        return line(
            amount: plan.target.spokenText(locale: locale),
            sets: "\(sets) sets of ",
            weight: shownWeight?.spokenText(locale: locale),
        )
        .joined(separator: ", ")
    }

    /// The amount, after the sets count unless there is one set, and per side when it is, then
    /// the weight, each when it is a pair's.
    private func line(amount: String, sets: String, weight: String?) -> [String] {
        var parts = [qualified(plan.sets > 1 ? sets + amount : amount, .target)]
        if let weight {
            parts.append(qualified(weight, .weight))
        }
        return parts
    }

    /// `text` followed by what a part's number is for, if anything: "per side" after reps or a
    /// time done one side at a time, "each" after a pair's weight.
    private func qualified(_ text: String, _ part: PlanPart) -> String {
        let qualifier: String? = switch part {
        case .sets: nil
        case .target: exercise.isPerSide ? "per side" : nil
        case .weight: exercise.load == .pair ? "each" : nil
        }
        return [text, qualifier].compactMap(\.self).joined(separator: " ")
    }

    /// A weight shows only on an exercise that holds one.
    private var shownWeight: Weight? {
        exercise.load == nil ? nil : plan.weight
    }
}

extension SetTarget {
    /// "1 rep", "10 reps", "30 s", "90 s", "2 min", "2:30 min".
    func text(locale: Locale) -> String {
        switch self {
        case let .reps(reps):
            "\(reps.formatted(.number.locale(locale)))\(noBreakSpace)\(reps == 1 ? "rep" : "reps")"
        case let .time(seconds):
            TimeText.text(seconds: seconds, locale: locale)
        }
    }

    /// "1 rep", "10 reps", "90 seconds", "2 minutes", "2 minutes 30 seconds".
    func spokenText(locale: Locale) -> String {
        switch self {
        case let .reps(reps):
            return counted(reps, "rep", "reps", locale: locale)
        case let .time(seconds):
            guard seconds >= TimeText.minutesFrom else {
                return counted(seconds, "second", "seconds", locale: locale)
            }
            let minutes = counted(seconds / 60, "minute", "minutes", locale: locale)
            guard seconds % 60 > 0 else { return minutes }
            return minutes + " " + counted(seconds % 60, "second", "seconds", locale: locale)
        }
    }
}

extension Weight {
    /// "50", "142.5", "1.25": no trailing zeros, at most two decimals.
    func number(locale: Locale) -> String {
        amount.formatted(.number.precision(.fractionLength(0 ... 2)).locale(locale))
    }

    /// "50 lb", "2.5 kg".
    func text(locale: Locale) -> String {
        number(locale: locale) + noBreakSpace + unit.rawValue
    }

    /// "50 pounds", "1 pound", "2.5 kilograms".
    func spokenText(locale: Locale) -> String {
        let one = amount == 1
        let name = switch unit {
        case .pounds: one ? "pound" : "pounds"
        case .kilograms: one ? "kilogram" : "kilograms"
        }
        return number(locale: locale) + " " + name
    }
}

/// A time reads in seconds under two minutes, then in minutes.
enum TimeText {
    static let minutesFrom = 120

    /// "30 s", "90 s", "2 min", "2:30 min".
    static func text(seconds: Int, locale: Locale) -> String {
        guard seconds >= minutesFrom else {
            return seconds.formatted(.number.locale(locale)) + noBreakSpace + "s"
        }
        let minutes = (seconds / 60).formatted(.number.locale(locale))
        let rest = seconds % 60
        guard rest > 0 else { return minutes + noBreakSpace + "min" }
        let seconds = rest.formatted(.number.precision(.integerLength(2...)).locale(locale))
        return minutes + ":" + seconds + noBreakSpace + "min"
    }
}

private func counted(_ count: Int, _ one: String, _ many: String, locale: Locale) -> String {
    "\(count.formatted(.number.locale(locale))) \(count == 1 ? one : many)"
}
