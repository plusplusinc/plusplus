import Foundation

/// The days Log reads over: four full calendar weeks ending with this week, each starting on the
/// calendar's first weekday, so the period's first day is the first day of the week three weeks
/// before this one, and its last day is today. History, Diff, and Balance all read from the
/// first day. A logged workout belongs to the day it started, in the calendar's time zone, as
/// its row's date reads: one that runs past midnight marks the day it began.
public struct LogPeriod: Equatable, Sendable {
    /// The weeks the period spans, this week's included.
    public static let weekCount = 4

    /// One day of the period.
    public struct Day: Identifiable, Equatable, Sendable {
        /// The start of the day.
        public let date: Date
        /// A finished logged workout started on it.
        public let hasWorkoutSession: Bool
        public let isToday: Bool
        /// After today, in this week's row: not drawn.
        public let isAfterToday: Bool

        public var id: Date {
            date
        }
    }

    /// The start of the period's first day.
    public let firstDay: Date
    /// The start of today, the period's last day.
    public let today: Date
    /// `weekCount` weeks of seven days, oldest first, each starting on the calendar's first
    /// weekday.
    public let weeks: [[Day]]
    /// The finished logged workouts that started in the period, up to `now`.
    public let workoutSessionCount: Int

    /// The period around `now`, with the days on which one of `workoutSessions` started. Logged
    /// workouts still in progress don't count.
    public init(workoutSessions: [WorkoutSession], calendar: Calendar, now: Date) {
        let firstDay = Self.firstDay(calendar: calendar, now: now)
        let today = calendar.startOfDay(for: now)
        let finished = workoutSessions.filter { !$0.isInProgress }.map(\.startedAt)
            .filter { $0 >= firstDay && $0 <= now }
        let workoutSessionDays = Set(finished.map { calendar.startOfDay(for: $0) })
        let days = (0 ..< Self.weekCount * 7).compactMap { offset -> Day? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
                return nil
            }
            let day = calendar.startOfDay(for: date)
            return Day(
                date: day,
                hasWorkoutSession: workoutSessionDays.contains(day),
                isToday: day == today,
                isAfterToday: day > today,
            )
        }
        self.firstDay = firstDay
        self.today = today
        weeks = stride(from: 0, to: days.count, by: 7).map { start in
            Array(days[start ..< min(start + 7, days.count)])
        }
        workoutSessionCount = finished.count
    }

    /// The start of the first day of the week `weekCount - 1` weeks before the one holding `now`.
    public static func firstDay(calendar: Calendar, now: Date) -> Date {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .weekOfYear, value: -(weekCount - 1), to: thisWeek)
            ?? thisWeek
        return calendar.startOfDay(for: first)
    }

    /// The calendar's one-letter weekday names, its first weekday first: "S M T W T F S".
    public static func weekdayInitials(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}
