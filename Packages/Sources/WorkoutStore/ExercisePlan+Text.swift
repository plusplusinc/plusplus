import Foundation

// How a plan reads: on its row, to VoiceOver, and in its sheet. Every number carries its unit
// but the sets count, joined by a no-break space so a line never breaks between them, and says
// whether it's per side or each.

private let noBreakSpace = "\u{00A0}"

extension RoutineExercise {
    /// The row's detail line in parts: the equipment if any, the plan, then the weight if it
    /// holds one.
    /// "Dumbbells, bench", "3 × 10 reps per side", "50 lb".
    public func detailParts(locale: Locale = .current) -> [String] {
        let sets = plan.sets.formatted(.number.locale(locale))
        return line(
            amount: plan.target.text(locale: locale),
            sets: "\(sets)\(noBreakSpace)×\(noBreakSpace)",
            weight: shownWeight?.text(locale: locale),
        )
    }

    /// The detail line in words, for VoiceOver: "Dumbbells, bench, 3 sets of 10 reps per side,
    /// 50 pounds".
    public func spokenDetail(locale: Locale = .current) -> String {
        let sets = plan.sets.formatted(.number.locale(locale))
        return line(
            amount: plan.target.spokenText(locale: locale),
            sets: "\(sets) sets of ",
            weight: shownWeight?.spokenText(locale: locale),
        )
        .joined(separator: ", ")
    }

    /// The equipment, then the amount, after the sets count unless there is one set, and per
    /// side when it is, then the weight, each when it is a pair's.
    private func line(amount: String, sets: String, weight: String?) -> [String] {
        var parts = exercise.equipmentLine.map { [$0] } ?? []
        let amount = plan.sets > 1 ? sets + amount : amount
        parts.append(exercise.isPerSide ? amount + " per side" : amount)
        if let weight {
            parts.append(exercise.load == .pair ? weight + " each" : weight)
        }
        return parts
    }

    /// A weight shows only on an exercise that holds one.
    private var shownWeight: Weight? {
        exercise.load == nil ? nil : plan.weight
    }

    /// A part's name in the sheet: "Sets", "Reps" or "Time", "Weight".
    public func label(of part: PlanPart) -> String {
        switch part {
        case .sets: "Sets"
        case .target:
            switch plan.target {
            case .reps: "Reps"
            case .time: "Time"
            }
        case .weight: "Weight"
        }
    }

    /// What a part's number means, under its name in the sheet: "Per side" for reps or time,
    /// and for a weight, what it is the weight of.
    public func note(of part: PlanPart) -> String? {
        switch part {
        case .sets: nil
        case .target: exercise.isPerSide ? "Per side" : nil
        case .weight:
            switch exercise.load {
            case .single:
                exercise.equipment.contains(.kettlebell) ? "One kettlebell" : "One dumbbell"
            case .pair: "Pair, each"
            case .bar: "Bar, total"
            case nil: nil
            }
        }
    }

    /// A part's value in the sheet, nil only for a weight on an exercise with none: 3, 60 s,
    /// 2:30 min, 135 lb.
    public func value(of part: PlanPart, locale: Locale = .current) -> PlanValue? {
        switch part {
        case .sets:
            PlanValue(plan.sets.formatted(.number.locale(locale)))
        case .target:
            switch plan.target {
            case let .reps(reps): PlanValue(reps.formatted(.number.locale(locale)))
            case let .time(seconds): TimeText.value(seconds: seconds, locale: locale)
            }
        case .weight:
            shownWeight.map { PlanValue($0.number(locale: locale), unit: $0.unit.rawValue) }
        }
    }

    /// A part's value in words, for VoiceOver: "3 sets", "10 reps", "2 minutes 30 seconds",
    /// "50 pounds".
    public func spokenValue(of part: PlanPart, locale: Locale = .current) -> String {
        switch part {
        case .sets: counted(plan.sets, "set", "sets", locale: locale)
        case .target: plan.target.spokenText(locale: locale)
        case .weight: shownWeight?.spokenText(locale: locale) ?? ""
        }
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

/// A number as the sheet shows it, with its unit drawn small after it, if it has one.
public struct PlanValue: Equatable, Sendable {
    public let number: String
    public let unit: String?

    public init(_ number: String, unit: String? = nil) {
        self.number = number
        self.unit = unit
    }
}

/// A time reads in seconds under two minutes, then in minutes.
enum TimeText {
    static let minutesFrom = 120

    /// "30 s", "90 s", "2 min", "2:30 min".
    static func text(seconds: Int, locale: Locale) -> String {
        let value = value(seconds: seconds, locale: locale)
        return value.number + noBreakSpace + (value.unit ?? "")
    }

    static func value(seconds: Int, locale: Locale) -> PlanValue {
        guard seconds >= minutesFrom else {
            return PlanValue(seconds.formatted(.number.locale(locale)), unit: "s")
        }
        let minutes = (seconds / 60).formatted(.number.locale(locale))
        let rest = seconds % 60
        guard rest > 0 else { return PlanValue(minutes, unit: "min") }
        let seconds = rest.formatted(.number.precision(.integerLength(2...)).locale(locale))
        return PlanValue(minutes + ":" + seconds, unit: "min")
    }
}

private func counted(_ count: Int, _ one: String, _ many: String, locale: Locale) -> String {
    "\(count.formatted(.number.locale(locale))) \(count == 1 ? one : many)"
}
