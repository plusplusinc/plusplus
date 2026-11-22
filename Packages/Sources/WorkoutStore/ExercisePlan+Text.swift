import Foundation

// How a plan reads: on its row, and to VoiceOver. Every number carries its unit
// but the sets count, joined by a no-break space so a line never breaks between them, and says
// whether it's per side: the reps or time, or a pair's weight ("20 lb/side").

let noBreakSpace = "\u{00A0}"

extension WorkoutExercise {
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

    /// "1 rep", "10 reps", "45 seconds", "2 minutes", "2 minutes, 30 seconds".
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
    /// The number alone, as the current exercise shows it large beside its unit: "50",
    /// "142.5", "1.25", no trailing zeros, at most two decimals.
    func number(locale: Locale) -> String {
        amount.formatted(.number.precision(.fractionLength(0 ... 2)).locale(locale))
    }

    /// As the system writes a mass at the abbreviated width, in its own unit: "50 lb",
    /// "2.5 kg"; with `decimals` 1 ... 2, "50.0 lb"; "27,5 lb" in de_DE. Joined by a no-break
    /// space.
    func text(locale: Locale, decimals: ClosedRange<Int> = 0 ... 2) -> String {
        formatted(width: .abbreviated, locale: locale, decimals: decimals)
            .replacing(" ", with: noBreakSpace)
    }

    /// The same at the wide width, for VoiceOver: "50 pounds", "1 pound", "2.5 kilograms".
    func spokenText(locale: Locale) -> String {
        formatted(width: .wide, locale: locale, decimals: 0 ... 2)
    }

    /// `usage: .asProvided` keeps the weight's own unit: the default converts to the region's.
    private func formatted(
        width: Measurement<UnitMass>.FormatStyle.UnitWidth,
        locale: Locale,
        decimals: ClosedRange<Int>,
    ) -> String {
        let mass = Measurement(value: amount, unit: unit == .pounds ? UnitMass.pounds : .kilograms)
        return mass.formatted(.measurement(
            width: width,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(decimals)),
        ).locale(locale))
    }
}

/// A time as the system writes it, in minutes and seconds: a value at the narrow width, a
/// sentence condensed, speech in full words.
enum TimeText {
    /// "30s", "1m 35s", "2m", "60m" in en_US; "1min 35s" in de_DE. Its parts joined by no-break
    /// spaces, so a line never breaks inside a time.
    static func text(seconds: Int, locale: Locale) -> String {
        formatted(seconds, width: .narrow, locale: locale)
    }

    /// A time inside a sentence, at the condensed width: "45 sec", "1 min 35 sec", "0 sec";
    /// "1 Min. 35 Sek." in de_DE. Joined by no-break spaces.
    static func inSentence(seconds: Int, locale: Locale) -> String {
        formatted(seconds, width: .condensedAbbreviated, locale: locale)
    }

    /// The narrow width with both units always, a zero one too: "0m 45s", "1m 0s", "1m 5s",
    /// "0m 0s"; "1min 0s" in de_DE. Joined by no-break spaces.
    static func bothUnits(seconds: Int, locale: Locale) -> String {
        formatted(seconds, width: .narrow, zeroValueUnits: .show(length: 1), locale: locale)
    }

    /// Minutes and seconds at `width`, joined by no-break spaces.
    private static func formatted(
        _ seconds: Int,
        width: Duration.UnitsFormatStyle.UnitWidth,
        zeroValueUnits: Duration.UnitsFormatStyle.ZeroValueUnitsDisplayStrategy = .hide,
        locale: Locale,
    ) -> String {
        Duration.seconds(seconds)
            .formatted(.units(
                allowed: [.minutes, .seconds],
                width: width,
                zeroValueUnits: zeroValueUnits,
            ).locale(locale))
            .replacing(" ", with: noBreakSpace)
    }

    /// In words, for VoiceOver, at the wide width: "45 seconds", "1 minute, 35 seconds",
    /// "2 minutes"; "1 Minute und 35 Sekunden" in de_DE.
    static func spoken(seconds: Int, locale: Locale) -> String {
        Duration.seconds(seconds)
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide).locale(locale))
    }
}

func counted(_ count: Int, _ one: String, _ many: String, locale: Locale) -> String {
    "\(count.formatted(.number.locale(locale))) \(count == 1 ? one : many)"
}
