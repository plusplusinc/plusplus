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

    /// Expected occurrences in one calendar week — the Quiet Arcade
    /// week block bar's denominator. Weekday schedules occur once per
    /// marked day; a pace normalizes to a 7-day window and rounds to
    /// the nearest whole session ("3×/7d" → 3, "1×/2d" → 4, "1×/10d"
    /// → 1 — a schedule that exists never rounds to zero).
    public var expectedSessionsPerWeek: Int {
        switch normalized {
        case .unscheduled:
            return 0
        case .weekdays(let days):
            return days.count
        case .frequency(let times, let perDays):
            return max(1, Int((Double(times) * 7 / Double(perDays)).rounded()))
        }
    }

    /// Pure due computation. `lastCompleted` is the most recent finished
    /// session of this routine (nil = never done); `previousCompleted`
    /// is the completion before THAT (nil if none) — the banking rule
    /// needs it to tell an extra session from a make-up. A completion
    /// on `today` always reads as not due — the schedule is satisfied.
    ///
    /// Weekday occurrences can also be satisfied EARLY (#267): a
    /// completion on an off day when nothing was outstanding banks the
    /// next scheduled day — one workout, one occurrence, Dave's ruling
    /// (the window logic lives in `occurrenceSatisfiedEarly`, shared
    /// with `dueSince` and `upcomingScheduledDays` so none can drift).
    ///
    /// Frequency stays rational instead of rounding to a fixed interval:
    /// "3× per 7 days" is due once `daysSince × times ≥ perDays`, so the
    /// slots average 2⅓ days rather than drifting to every-3-days.
    /// Frequency ignores `previousCompleted` — anchoring to the last
    /// completion already re-slots early sessions.
    public func dueState(lastCompleted: Date?, previousCompleted: Date? = nil, today: Date, calendar: Calendar) -> DueState {
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
            let completedDay = lastCompleted.map { calendar.startOfDay(for: $0) }
            let previousDay = previousCompleted.map { calendar.startOfDay(for: $0) }
            if Self.oldestOutstandingScheduledDay(
                onOrBefore: todayStart, days: days,
                completedDay: completedDay, previousCompleted: previousDay, calendar: calendar
            ) != nil {
                return .due
            }
            // The next unsatisfied scheduled day. 14 days bounds the
            // walk: the nearest scheduled day is within 7, and the one
            // completion can bank at most one occurrence, so the day
            // after the banked one is within 14.
            if let next = Self.unsatisfiedScheduledDays(
                after: todayStart, withinDays: 14, days: days,
                completedDay: completedDay, previousCompleted: previousDay, calendar: calendar
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
    public func dueSince(lastCompleted: Date?, previousCompleted: Date? = nil, today: Date, calendar: Calendar) -> Date? {
        guard case .due = dueState(
            lastCompleted: lastCompleted, previousCompleted: previousCompleted,
            today: today, calendar: calendar
        ) else { return nil }
        let todayStart = calendar.startOfDay(for: today)
        switch normalized {
        case .unscheduled:
            return nil
        case .weekdays(let days):
            // The guard above means the shared walk finds a day; the
            // fallback only quiets the optional.
            return Self.oldestOutstandingScheduledDay(
                onOrBefore: todayStart, days: days,
                completedDay: lastCompleted.map { calendar.startOfDay(for: $0) },
                previousCompleted: previousCompleted.map { calendar.startOfDay(for: $0) },
                calendar: calendar
            ) ?? todayStart
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
        previousCompleted: Date? = nil,
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
            return Self.unsatisfiedScheduledDays(
                after: todayStart, withinDays: horizon, days: days,
                completedDay: lastCompleted.map { calendar.startOfDay(for: $0) },
                previousCompleted: previousCompleted.map { calendar.startOfDay(for: $0) },
                calendar: calendar
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
    /// banked when the last completion falls strictly inside its window
    /// (previous scheduled day, day) AND nothing was outstanding on the
    /// day it happened — one workout, one occurrence (Dave's ruling): a
    /// make-up of a missed/carried day discharges THAT occurrence and
    /// nothing more; only a genuine extra session banks the next one.
    ///
    /// The lower bound is exclusive so a completion ON a scheduled day
    /// satisfies that day only (Monday's session never quiets
    /// Tuesday's). Completions at-or-after `day` are the
    /// late-satisfaction law, handled where past occurrences are walked
    /// (those loops break at the completion day).
    ///
    /// Due-ness at the completion is judged against `previousCompleted`
    /// one level deep — with no deeper history the completion day reads
    /// as MORE due (nil = never done = due), so the cutoff errs toward
    /// discharging, never double-banking. The recursion terminates: the
    /// inner call carries nil `previousCompleted`, and its own inner
    /// checks then see a nil completion and bail.
    private static func occurrenceSatisfiedEarly(on day: Date, days: Set<Int>, completedDay: Date?, previousCompleted: Date?, calendar: Calendar) -> Bool {
        guard let completedDay, completedDay < day else { return false }
        guard let previous = previousScheduledDay(before: day, days: days, calendar: calendar),
              completedDay > previous else { return false }
        let dueAtCompletion = RoutineSchedule.weekdays(days).dueState(
            lastCompleted: previousCompleted,
            today: completedDay,
            calendar: calendar
        )
        return dueAtCompletion != .due
    }

    /// The oldest scheduled day that has arrived (≤ today) and is
    /// neither discharged by a completion at-or-after it nor banked by
    /// an early one — the one backward walk behind `.due` and
    /// `dueSince`, so the two can't drift. Nil when nothing is
    /// outstanding. Only the FIRST scheduled day after a completion can
    /// be banked, so skipping it and breaking at the completion day
    /// still visits every candidate.
    private static func oldestOutstandingScheduledDay(
        onOrBefore todayStart: Date,
        days: Set<Int>,
        completedDay: Date?,
        previousCompleted: Date?,
        calendar: Calendar
    ) -> Date? {
        var oldest: Date?
        for offset in 0...6 {
            guard let candidate = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            if let completedDay, candidate <= completedDay { break }
            if days.contains(calendar.component(.weekday, from: candidate)),
               !occurrenceSatisfiedEarly(on: candidate, days: days, completedDay: completedDay, previousCompleted: previousCompleted, calendar: calendar) {
                oldest = candidate
            }
        }
        return oldest
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
        previousCompleted: Date?,
        calendar: Calendar
    ) -> [Date] {
        guard dayCount >= 1 else { return [] }
        var result: [Date] = []
        for offset in 1...dayCount {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            guard days.contains(calendar.component(.weekday, from: candidate)),
                  !occurrenceSatisfiedEarly(on: candidate, days: days, completedDay: completedDay, previousCompleted: previousCompleted, calendar: calendar)
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

    /// The ongoing-pattern phrasing for a cadence summary that sits
    /// beside concrete dated occurrences (the Today "beyond this week"
    /// line): it must read as the recurring rhythm, not a single day, or
    /// "sat" reads as a duplicate of the Saturday card right next to it.
    ///
    /// Fixed days lead with "every" so the recurrence is explicit
    /// ("every sat", "every mon/thu"); a rolling frequency reads as a
    /// rate that never names a weekday ("3×/wk", "weekly", "every 2d"),
    /// which is exactly what tells the two scheduling styles apart at a
    /// glance. Distinct from `shortLabel`, the terse chip/pill token.
    public var recurrenceLabel: String {
        switch normalized {
        case .unscheduled:
            return "anytime"
        case .weekdays:
            return "every \(shortLabel)"
        case .frequency(let times, let perDays):
            switch (times, perDays) {
            case (1, 1):
                return "daily"
            case (1, 7):
                return "weekly"
            case (1, _):
                return "every \(perDays)d"
            case (_, 7):
                return "\(times)×/wk"
            case (_, 1):
                return "\(times)×/day"
            default:
                return "\(times)×/\(perDays)d"
            }
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
