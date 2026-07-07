import Foundation

/// When a workout wants to happen (#83). Two modes mirror how people
/// actually schedule: fixed weekdays ("Mon / Wed / Fri") and rolling
/// frequency ("3× every 7 days"). Pure logic — storage and surfacing
/// live in the app; nothing here reads a clock.
public enum WorkoutSchedule: Equatable, Sendable {
    /// No schedule — the workout is done whenever.
    case unscheduled
    /// Fixed days of the week. Values are Calendar weekday numbers
    /// (1 = Sunday … 7 = Saturday), matching `DateComponents.weekday`
    /// so no locale math is needed at the call site.
    case weekdays(Set<Int>)
    /// Rolling frequency: `times` sessions every `perDays` days,
    /// anchored to the last completion rather than the calendar week.
    case frequency(times: Int, perDays: Int)

    /// Where a workout stands relative to its schedule on a given day.
    public enum DueState: Equatable, Sendable {
        /// The workout has no schedule; there is nothing to be due.
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
    public var normalized: WorkoutSchedule {
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
    /// session of this workout (nil = never done). A completion on
    /// `today` always reads as not due — the schedule is satisfied.
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
            let completedToday = lastCompleted.map { calendar.isDate($0, inSameDayAs: today) } ?? false
            if days.contains(calendar.component(.weekday, from: today)) && !completedToday {
                return .due
            }
            for offset in 1...7 {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: todayStart) else { continue }
                if days.contains(calendar.component(.weekday, from: candidate)) {
                    return .notDue(nextDue: candidate)
                }
            }
            // Unreachable: normalized weekdays are non-empty, so one of
            // the next 7 days matches. Satisfy the compiler harmlessly.
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

extension WorkoutSchedule: Codable {
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
