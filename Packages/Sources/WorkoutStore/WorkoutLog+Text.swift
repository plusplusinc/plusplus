import Foundation

// How Log reads: its figures, changes, and lines, and the sentences VoiceOver reads for them. A
// time is a clock, "0:45", as a change in it is, "+0:15". Every number keeps its unit beside it
// with a no-break space, so a line never breaks between them.

private let minus = "\u{2212}"

extension TopSet {
    /// "10 × 50 lb", "10 × 25 lb/side" on a pair, "10" with no weight, "0:45", "0:45 × 20 lb".
    public func figure(load: Load?, locale: Locale = .current) -> String {
        Self.figure(
            amount: target.figureText(locale: locale),
            weight: weight,
            load: load,
            locale: locale,
        )
    }

    /// "10 reps at 50 pounds", "10 reps at 25 pounds per side", "45 seconds".
    public func spokenFigure(load: Load?, locale: Locale = .current) -> String {
        let amount = target.spokenText(locale: locale)
        guard let weight else { return amount }
        let perSide = load == .pair ? " per side" : ""
        return "\(amount) at \(weight.spokenText(locale: locale))\(perSide)"
    }

    static func figure(amount: String, weight: Weight?, load: Load?, locale: Locale) -> String {
        guard let weight else { return amount }
        let side = load == .pair ? "/side" : ""
        return "\(amount)\(noBreakSpace)×\(noBreakSpace)\(weight.text(locale: locale))\(side)"
    }
}

extension LoggedRound {
    /// As its top set reads, but with sides that differ, both, left then right: "0:48/1:00".
    public func figure(load: Load?, locale: Locale = .current) -> String {
        let amounts = sides.map(\.target.amount)
        guard sides.count > 1, Set(amounts).count > 1 else {
            return topSet.figure(load: load, locale: locale)
        }
        let amount = ordered.map { $0.target.figureText(locale: locale) }.joined(separator: "/")
        return TopSet.figure(amount: amount, weight: counted.weight, load: load, locale: locale)
    }

    /// "left 48 seconds, right 1 minute" where the sides differ, else as its top set reads.
    public func spokenFigure(load: Load?, locale: Locale = .current) -> String {
        let amounts = sides.map(\.target.amount)
        guard sides.count > 1, Set(amounts).count > 1 else {
            return topSet.spokenFigure(load: load, locale: locale)
        }
        return ordered
            .map { "\($0.side?.rawValue ?? "") \($0.target.spokenText(locale: locale))" }
            .joined(separator: ", ")
    }

    private var ordered: [LoggedSet] {
        sides.sorted { ($0.side == .left ? 0 : 1) < ($1.side == .left ? 0 : 1) }
    }
}

extension SetTarget {
    /// "10" for reps, "0:45" for a time.
    func figureText(locale: Locale) -> String {
        switch self {
        case let .reps(reps): reps.formatted(.number.locale(locale))
        case let .time(seconds): Self.clock(seconds, locale: locale)
        }
    }

    /// "0:45", "1:00", "12:30".
    static func clock(_ seconds: Int, locale: Locale) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond).locale(locale))
    }
}

extension Change {
    /// "+15 lb", "+0:15", "+3", "+2 reps", "Same", "First time", "−10 lb"; nil for `.changed`.
    public func text(locale: Locale = .current) -> String? {
        switch self {
        case .first: "First time"
        case .same: "Same"
        case let .up(gain): "+" + gain.text(locale: locale)
        case let .down(gain): minus + gain.text(locale: locale)
        case .changed: nil
        }
    }

    /// "Up 15 pounds", "Same as last time", "First time", "Down 10 pounds"; nil for `.changed`.
    public func spokenText(locale: Locale = .current) -> String? {
        switch self {
        case .first: "First time"
        case .same: "Same as last time"
        case let .up(gain): "Up " + gain.spokenText(locale: locale)
        case let .down(gain): "Down " + gain.spokenText(locale: locale)
        case .changed: nil
        }
    }
}

extension Gain {
    func text(locale: Locale) -> String {
        switch self {
        case let .weight(weight): weight.text(locale: locale)
        case let .reps(reps, false): reps.formatted(.number.locale(locale))
        case let .reps(reps, true):
            counted(reps, "rep", "reps", locale: locale).replacing(" ", with: noBreakSpace)
        case let .seconds(seconds): SetTarget.clock(seconds, locale: locale)
        }
    }

    func spokenText(locale: Locale) -> String {
        switch self {
        case let .weight(weight): weight.spokenText(locale: locale)
        case let .reps(reps, _): counted(reps, "rep", "reps", locale: locale)
        case let .seconds(seconds): TimeText.spoken(seconds: seconds, locale: locale)
        }
    }
}

extension LoggedExercise {
    /// Its rounds' figures, joined: "10 × 50 lb · 10 × 50 lb".
    public func figures(locale: Locale = .current) -> String {
        rounds.map { $0.figure(load: exercise?.load, locale: locale) }.joined(separator: " · ")
    }

    /// The quiet line under its figures: "Per side." for one done a side at a time, then a note
    /// for each round short of its plan, "Set 2 planned at 1:00.", "Last set planned at 8."; nil
    /// for none.
    public func detail(locale: Locale = .current) -> String? {
        var parts: [String] = isPerSide ? ["Per side."] : []
        for (index, round) in rounds.enumerated() where round.isShort {
            let planned = round.sides.map(\.plannedLength).max() ?? 0
            let target = round.counted.plannedTarget
            let length = target.isTime
                ? SetTarget.clock(planned, locale: locale)
                : planned.formatted(.number.locale(locale))
            let which = index == rounds.count - 1
                ? "Last set"
                : "Set \((index + 1).formatted(.number.locale(locale)))"
            parts.append("\(which) planned at \(length).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// "Dumbbell row. Up 5 pounds. 3 sets: 10 reps at 25 pounds, …. Per side."
    public func spoken(change: Change, locale: Locale = .current) -> String {
        let count = counted(rounds.count, "set", "sets", locale: locale)
        let sets = rounds.map { $0.spokenFigure(load: exercise?.load, locale: locale) }
            .joined(separator: ", ")
        return [
            name,
            change.spokenText(locale: locale),
            "\(count): \(sets)",
            detail(locale: locale),
        ]
        .compactMap(\.self)
        .joined(separator: ". ")
    }
}

extension LoggedWorkout {
    /// "Thu, Nov 19 · 51 min", and with `sets`, "Thu, Nov 19 · 51 min · 21 sets".
    public func logLine(
        sets: Int? = nil,
        locale: Locale = .current,
        calendar: Calendar = .current,
    ) -> String {
        var parts = [dayText(locale: locale, calendar: calendar), lengthText(locale: locale)]
        if let sets {
            parts.append(counted(sets, "set", "sets", locale: locale))
        }
        return parts.joined(separator: " · ")
    }

    /// "Thursday, November 19, 51 minutes", for VoiceOver.
    public func spokenLogLine(
        sets: Int? = nil,
        locale: Locale = .current,
        calendar: Calendar = .current,
    ) -> String {
        let style = dateStyle(locale: locale, calendar: calendar).weekday(.wide).month(.wide).day()
        var parts = [
            startedAt.formatted(style),
            elapsed(at: endedAt ?? startedAt)
                .formatted(.units(allowed: [.hours, .minutes], width: .wide).locale(locale)),
        ]
        if let sets {
            parts.append(counted(sets, "set", "sets", locale: locale))
        }
        return parts.joined(separator: ", ")
    }

    /// "Sun, Nov 22", the day it was started: what tells one time through a workout from another.
    public func dayText(locale: Locale, calendar: Calendar) -> String {
        startedAt.formatted(
            dateStyle(locale: locale, calendar: calendar)
                .weekday(.abbreviated).month(.abbreviated).day(),
        )
    }

    /// "51 min", "1 hr 5 min".
    private func lengthText(locale: Locale) -> String {
        elapsed(at: endedAt ?? startedAt)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale))
            .replacing(",", with: "")
    }
}

extension GroupRecency {
    /// "Core, 0 sets", read after Balance's "Sets" caption.
    public func spokenText(locale: Locale = .current) -> String {
        "\(group.name), \(counted(sets, "set", "sets", locale: locale))"
    }
}

extension LogPeriod {
    /// The period from its first day to today, as the system writes a range of days: "Oct 25 –
    /// Nov 21", "Nov 1 – 21" within one month, a year on each side across one.
    public func rangeText(locale: Locale = .current, calendar: Calendar = .current) -> String {
        (firstDay ..< today).formatted(
            Date.IntervalFormatStyle(
                locale: locale,
                calendar: calendar,
                timeZone: calendar.timeZone,
            )
            .month(.abbreviated).day(),
        )
    }

    /// "October 25 to November 21", for VoiceOver: the range in words, not a dash.
    public func spokenRange(locale: Locale = .current, calendar: Calendar = .current) -> String {
        let style = dateStyle(locale: locale, calendar: calendar).month(.wide).day()
        return "\(firstDay.formatted(style)) to \(today.formatted(style))"
    }

    /// The day of the month, "25", as its calendar square shows it.
    public static func dayNumber(
        _ day: Day,
        locale: Locale = .current,
        calendar: Calendar = .current,
    ) -> String {
        day.date.formatted(dateStyle(locale: locale, calendar: calendar).day())
    }

    /// "9 workouts", "1 workout".
    public func loggedWorkoutCountText(locale: Locale = .current) -> String {
        counted(loggedWorkoutCount, "workout", "workouts", locale: locale)
    }

    /// "Saturday, November 21, workout", "Friday, November 20, no workout", for VoiceOver.
    public static func spokenDay(
        _ day: Day,
        locale: Locale = .current,
        calendar: Calendar = .current,
    ) -> String {
        let date = day.date.formatted(
            dateStyle(locale: locale, calendar: calendar).weekday(.wide).month(.wide).day(),
        )
        let today = day.isToday ? "Today, " : ""
        return "\(today)\(date), \(day.hasLoggedWorkout ? "workout" : "no workout")"
    }
}

/// Dates in `calendar`'s own time zone, so a day reads as the calendar marks it.
private func dateStyle(locale: Locale, calendar: Calendar) -> Date.FormatStyle {
    Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
}
