import Foundation

/// When a routine wants to happen (#83). Two modes mirror how people
/// actually schedule: fixed weekdays ("Mon / Wed / Fri") and rolling
/// frequency ("3× every 7 days"). Pure logic — storage and surfacing
/// live in the app; nothing here reads a clock.
public enum RoutineSchedule: Equatable, Sendable {
    /// No schedule — the routine is done whenever.
    case unscheduled
    /// Fixed days of the week. Values are Calendar weekday numbers
    /// (1 = Sunday … 7 = Saturday), matching `DateComponents.weekday`
    /// so no locale math is needed at the call site.
    case weekdays(Set<Int>)
    /// Rolling frequency: `times` sessions every `perDays` days,
    /// anchored to the last completion rather than the calendar week.
    case frequency(times: Int, perDays: Int)

    /// Where a routine stands relative to its schedule on a given day.
    public enum DueState: Equatable, Sendable {
        /// The routine has no schedule; there is nothing to be due.
        case unscheduled
        /// Scheduled for today (or overdue) and not yet done today.
        case due
        /// Not today; `nextDue` is the start of the next scheduled day.
        case notDue(nextDue: Date)
    }

    /// Out-of-range weekdays are dropped (an empty result means no
    /// schedule at all), frequency counts are clamped to at least 1.
    /// Decoding normalizes, so hand-edited JSON can't smuggle in an
    /// impossible schedule.
    public var normalized: RoutineSchedule {
        switch self {
        case .unscheduled:
            return .unscheduled
        case .weekdays(let days):
            let valid = days.filter { (1...7).contains($0) }
            return valid.isEmpty ? .unscheduled : .weekdays(valid)
        case .frequency(let times, let perDays):
            return .frequency(times: max(1, times), perDays: max(1, perDays))
        }
    }

    /// Pure due computation. `lastCompleted` is the most recent finished
    /// session of this routine (nil = never done). A completion on
    /// `today` always reads as not due — the schedule is satisfied.
    ///
    /// Weekday occurrences can also be satisfied EARLY (#267): a
    /// completion on an off day banks the next scheduled day — one
    /// satisfaction per inter-occurrence window (the window logic lives
    /// in `occurrenceSatisfiedEarly`, shared with
    /// `upcomingScheduledDays` so the two can't drift).
    ///
    /// Frequency stays rational instead of rounding to a fixed interval:
    /// "3× per 7 days" is due once `daysSince × times ≥ perDays`, so the
    /// slots average 2⅓ days rather than drifting to every-3-days.
    public func dueState(lastCompleted: Date?, today: Date, calendar: Calendar) -> DueState {
        let todayStart = calendar.startOfDay(for: today)
        switch normalized {
        case .unscheduled:
            return .unscheduled

        case .weekdays(let days):
            // Due when any scheduled day since the last completion has
            // arrived and gone unmet — a missed Thursday keeps the
            // routine due through Friday (§3's "due since thu"), and
            // completing it then satisfies that occurrence. Occurrences
            // never stack: one due-ness, however many days were missed.
            // A day the completion already banked is skipped, not
            // returned — only the FIRST scheduled day after a completion
            // can be banked, so everything older still breaks the loop
            // at the completion day.
            let completedDay = lastCompleted.map { calendar.startOfDay(for: $0) }
            for offset in 0...6 {
                guard let candidate = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
                if let completedDay, candidate <= completedDay { break }
                if days.contains(calendar.component(.weekday, from: candidate)),
                   !Self.occurrenceSatisfiedEarly(on: candidate, days: days, completedDay: completedDay, calendar: calendar) {
                    return .due
                }
            }
            // The next unsatisfied scheduled day. 14 days bounds the
            // walk: the nearest scheduled day is within 7, and the one
            // completion can bank at most one occurrence, so the day
            // after the banked one is within 14.
            if let next = Self.unsatisfiedScheduledDays(
                after: todayStart, withinDays: 14, days: days,
                completedDay: completedDay, calendar: calendar
            ).first {
                return .notDue(nextDue: next)
            }
            // Unreachable: normalized weekdays are non-empty, so one of
            // the next 14 days is an unsatisfied occurrence. Satisfy the
            // compiler harmlessly.
            return .notDue(nextDue: todayStart)

        case .frequency(let times, let perDays):
            guard let last = lastCompleted else { return .due }
            let lastStart = calendar.startOfDay(for: last)
            let daysSince = calendar.dateComponents([.day], from: lastStart, to: todayStart).day ?? 0
            if daysSince * times >= perDays {
                return .due
            }
            let interval = (perDays + times - 1) / times
            let next = calendar.date(byAdding: .day, value: interval, to: lastStart) ?? todayStart
            return .notDue(nextDue: next)
        }
    }
}

extension RoutineSchedule {
    /// The day the current due-ness began — today for an on-time
    /// routine, the missed day for an overdue one ("due since thu").
    /// Nil when the routine isn't due at all.
    public func dueSince(lastCompleted: Date?, today: Date, calendar: Calendar) -> Date? {
        guard case .due = dueState(lastCompleted: lastCompleted, today: today, calendar: calendar) else { return nil }
        let todayStart = calendar.startOfDay(for: today)
        switch normalized {
        case .unscheduled:
            return nil
        case .weekdays(let days):
            let completedDay = lastCompleted.map { calendar.startOfDay(for: $0) }
            var oldest = todayStart
            for offset in 0...6 {
                guard let candidate = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
                if let completedDay, candidate <= completedDay { break }
                if days.contains(calendar.component(.weekday, from: candidate)),
                   !Self.occurrenceSatisfiedEarly(on: candidate, days: days, completedDay: completedDay, calendar: calendar) {
                    oldest = candidate
                }
            }
            return oldest
        case .frequency(let times, let perDays):
            guard let last = lastCompleted else { return todayStart }
            let interval = (perDays + times - 1) / times
            let since = calendar.date(byAdding: .day, value: interval, to: calendar.startOfDay(for: last)) ?? todayStart
            return min(since, todayStart)
        }
    }

    /// The day-starts strictly after `today`, within `horizon` days
    /// (inclusive of today + horizon), on which this routine would
    /// surface as scheduled — assuming nothing gets completed in
    /// between (#267, the Today week-ahead).
    ///
    /// Weekday schedules list their occurrence days, minus any
    /// occurrence the last completion already banked — the same window
    /// logic `dueState` uses, so the two can't drift. A carried-over
    /// missed day is today's business (it rides today's due card) and
    /// never re-appears as a future entry: only real occurrence days
    /// are returned, never the carried tail. Frequency schedules
    /// predict the single next due day from the completion anchor;
    /// unscheduled routines have no days at all.
    public func upcomingScheduledDays(
        lastCompleted: Date?,
        today: Date,
        horizon: Int = 7,
        calendar: Calendar
    ) -> [Date] {
        guard horizon >= 1 else { return [] }
        let todayStart = calendar.startOfDay(for: today)
        switch normalized {
        case .unscheduled:
            return []

        case .weekdays(let days):
            let completedDay = lastCompleted.map { calendar.startOfDay(for: $0) }
            return Self.unsatisfiedScheduledDays(
                after: todayStart, withinDays: horizon, days: days,
                completedDay: completedDay, calendar: calendar
            )

        case .frequency:
            // Anchored to the last completion. Due now (never done, or
            // overdue) is today's business — the carried tail never
            // previews; otherwise the single predicted day, horizon
            // permitting.
            guard case .notDue(let next) = dueState(lastCompleted: lastCompleted, today: today, calendar: calendar),
                  let boundary = calendar.date(byAdding: .day, value: horizon, to: todayStart),
                  next <= boundary
            else { return [] }
            return [next]
        }
    }

    /// The last scheduled day strictly before `day` — the lower edge of
    /// an occurrence's satisfaction window. Non-nil for any non-empty
    /// weekday set (seven steps cover the week).
    private static func previousScheduledDay(before day: Date, days: Set<Int>, calendar: Calendar) -> Date? {
        for offset in 1...7 {
            guard let candidate = calendar.date(byAdding: .day, value: -offset, to: day) else { continue }
            if days.contains(calendar.component(.weekday, from: candidate)) {
                return candidate
            }
        }
        return nil
    }

    /// Early satisfaction (#267): the occurrence on scheduled `day` is
    /// already banked when the last completion falls strictly inside
    /// its window (previous scheduled day, day) — one satisfaction per
    /// inter-occurrence window. The lower bound is exclusive so a
    /// completion ON a scheduled day satisfies that day only (Monday's
    /// session never quiets Tuesday's). Completions at-or-after `day`
    /// are the late-satisfaction law, handled where past occurrences
    /// are walked (those loops break at the completion day).
    private static func occurrenceSatisfiedEarly(on day: Date, days: Set<Int>, completedDay: Date?, calendar: Calendar) -> Bool {
        guard let completedDay, completedDay < day else { return false }
        guard let previous = previousScheduledDay(before: day, days: days, calendar: calendar) else { return false }
        return completedDay > previous
    }

    /// Scheduled days strictly after `start`, in day order, skipping
    /// occurrences the completion already banked — the one forward walk
    /// behind both `.notDue(nextDue:)` and `upcomingScheduledDays`, so
    /// a banked day vanishes from both or neither.
    private static func unsatisfiedScheduledDays(
        after start: Date,
        withinDays dayCount: Int,
        days: Set<Int>,
        completedDay: Date?,
        calendar: Calendar
    ) -> [Date] {
        guard dayCount >= 1 else { return [] }
        var result: [Date] = []
        for offset in 1...dayCount {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            guard days.contains(calendar.component(.weekday, from: candidate)),
                  !occurrenceSatisfiedEarly(on: candidate, days: days, completedDay: completedDay, calendar: calendar)
            else { continue }
            result.append(candidate)
        }
        return result
    }

    /// Terse display label: "mon/thu" (Monday-first), "2×/7d", or
    /// "no schedule" — the chip/pill vocabulary shared by the routine
    /// detail header, routine cards, and the Today meta line.
    public var shortLabel: String {
        switch normalized {
        case .unscheduled:
            return "no schedule"
        case .weekdays(let days):
            let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
            let mondayFirst = days.sorted { (($0 + 5) % 7) < (($1 + 5) % 7) }
            return mondayFirst.map { names[$0 - 1] }.joined(separator: "/")
        case .frequency(let times, let perDays):
            return "\(times)×/\(perDays)d"
        }
    }
}

extension RoutineSchedule: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode, weekdays, times, perDays
    }

    private enum Mode: String, Codable {
        case unscheduled, weekdays, frequency
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .unscheduled:
            self = .unscheduled
        case .weekdays:
            self = .weekdays(try container.decode(Set<Int>.self, forKey: .weekdays)).normalized
        case .frequency:
            self = .frequency(
                times: try container.decode(Int.self, forKey: .times),
                perDays: try container.decode(Int.self, forKey: .perDays)
            ).normalized
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch normalized {
        case .unscheduled:
            try container.encode(Mode.unscheduled, forKey: .mode)
        case .weekdays(let days):
            try container.encode(Mode.weekdays, forKey: .mode)
            try container.encode(days.sorted(), forKey: .weekdays)
        case .frequency(let times, let perDays):
            try container.encode(Mode.frequency, forKey: .mode)
            try container.encode(times, forKey: .times)
            try container.encode(perDays, forKey: .perDays)
        }
    }
}
