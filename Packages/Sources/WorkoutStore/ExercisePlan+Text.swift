import Foundation

// How a plan reads: on its row, and to VoiceOver. Every number carries its unit
// but the sets count, joined by a no-break space so a line never breaks between them, and says
// whether it's per side: the reps or time, or a pair's weight ("20 lb/side").

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
            spoken: false,
        )
    }

    /// The detail line in words, for VoiceOver: "3 sets of 10 reps per side, 50 pounds".
    public func spokenDetail(locale: Locale = .current) -> String {
        let sets = plan.sets.formatted(.number.locale(locale))
        return line(
            amount: plan.target.spokenText(locale: locale),
            sets: "\(sets) sets of ",
            weight: shownWeight?.spokenText(locale: locale),
            spoken: true,
        )
        .joined(separator: ", ")
    }

    /// The amount, after the sets count unless there is one set, and per side when it is, then
    /// the weight, per side when it is a pair's.
    private func line(amount: String, sets: String, weight: String?, spoken: Bool) -> [String] {
        var parts = [qualified(plan.sets > 1 ? sets + amount : amount, .target)]
        if let weight {
            parts.append(qualified(weight, .weight, spoken: spoken))
        }
        return parts
    }

    /// `text` followed by what a part's number is for, if anything: "per side" after reps or a
    /// time done one side at a time, "/side" after a pair's weight ("20 lb/side"), spoken
    /// "per side".
    func qualified(_ text: String, _ part: PlanPart, spoken: Bool = false) -> String {
        switch part {
        case .sets, .rest: text
        case .target: exercise.isPerSide ? text + " per side" : text
        case .weight:
            exercise.load == .pair ? text + (spoken ? " per side" : "/side") : text
        }
    }

    /// A weight shows only on an exercise that holds one.
    var shownWeight: Weight? {
        exercise.load == nil ? nil : plan.weight
    }
}

extension SetTarget {
    /// "1 rep", "10 reps", "30s", "1m 35s", "2m".
    func text(locale: Locale) -> String {
        switch self {
        case let .reps(reps): counted(reps, "rep", "reps", locale: locale)
            .replacing(" ", with: noBreakSpace)
        case let .time(seconds): TimeText.text(seconds: seconds, locale: locale)
        }
    }

    /// "1 rep", "10 reps", "90 seconds", "2 minutes", "2 minutes 30 seconds".
    func spokenText(locale: Locale) -> String {
        switch self {
        case let .reps(reps):
            counted(reps, "rep", "reps", locale: locale)
        case let .time(seconds):
            TimeText.spoken(seconds: seconds, locale: locale)
        }
    }
}

extension Weight {
    /// "50", "142.5", "1.25": no trailing zeros, at most two decimals.
    func number(locale: Locale, decimals: ClosedRange<Int> = 0 ... 2) -> String {
        amount.formatted(.number.precision(.fractionLength(decimals)).locale(locale))
    }

    /// "50 lb", "2.5 kg"; with `decimals` 1 ... 2, "50.0 lb".
    func text(locale: Locale, decimals: ClosedRange<Int> = 0 ... 2) -> String {
        number(locale: locale, decimals: decimals) + noBreakSpace + unit.rawValue
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

/// A time as the system writes it, in minutes and seconds at the narrow width, and as a clock.
enum TimeText {
    static let minutesFrom = 120

    /// "30s", "1m 35s", "2m", "60m" in en_US; "1min 35s" in de_DE. Its parts joined by no-break
    /// spaces, so a line never breaks inside a time.
    static func text(seconds: Int, locale: Locale) -> String {
        Duration.seconds(seconds)
            .formatted(.units(allowed: [.minutes, .seconds], width: .narrow).locale(locale))
            .replacing(" ", with: noBreakSpace)
    }

    /// A time inside a sentence, at the condensed width: "45 sec", "1 min 35 sec", "0 sec";
    /// "1 Min. 35 Sek." in de_DE. Joined by no-break spaces.
    static func inSentence(seconds: Int, locale: Locale) -> String {
        Duration.seconds(seconds)
            .formatted(.units(allowed: [.minutes, .seconds], width: .condensedAbbreviated)
                .locale(locale))
            .replacing(" ", with: noBreakSpace)
    }

    /// Minutes and two-digit seconds, "0:45", "1:35", "60:00".
    static func clock(seconds: Int, locale: Locale) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond).locale(locale))
    }

    /// "90 seconds", "2 minutes", "2 minutes 30 seconds".
    static func spoken(seconds: Int, locale: Locale) -> String {
        guard seconds >= minutesFrom else {
            return counted(seconds, "second", "seconds", locale: locale)
        }
        let minutes = counted(seconds / 60, "minute", "minutes", locale: locale)
        guard seconds % 60 > 0 else { return minutes }
        return minutes + " " + counted(seconds % 60, "second", "seconds", locale: locale)
    }
}

func counted(_ count: Int, _ one: String, _ many: String, locale: Locale) -> String {
    "\(count.formatted(.number.locale(locale))) \(count == 1 ? one : many)"
}
