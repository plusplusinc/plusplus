import Foundation

/// The days Log reads over: four full calendar weeks ending with this week, each starting on the
/// calendar's first weekday, so the period's first day is the first day of the week three weeks
/// before this one. Workouts, Diff, and Gaps all read from that day. A logged workout belongs to
/// the day it finished, in the calendar's time zone.
public struct LogPeriod: Equatable, Sendable {
    /// The weeks the period spans, this week's included.
    public static let weekCount = 4

    /// One day of the period.
    public struct Day: Identifiable, Equatable, Sendable {
        /// The start of the day.
        public let date: Date
        /// A finished logged workout ended on it.
        public let hasLoggedWorkout: Bool
        public let isToday: Bool
        /// After today, in this week's row: not drawn.
        public let isAfterToday: Bool

        public var id: Date {
            date
        }
    }

    /// The start of the period's first day.
    public let firstDay: Date
    /// `weekCount` weeks of seven days, oldest first, each starting on the calendar's first
    /// weekday.
    public let weeks: [[Day]]
    /// The finished logged workouts that ended in the period, up to `now`.
    public let loggedWorkoutCount: Int

    /// The period around `now`, with the days on which one of `loggedWorkouts` finished. Logged
    /// workouts still in progress don't count.
    public init(loggedWorkouts: [LoggedWorkout], calendar: Calendar, now: Date) {
        let firstDay = Self.firstDay(calendar: calendar, now: now)
        let today = calendar.startOfDay(for: now)
        let finished = loggedWorkouts.compactMap(\.endedAt).filter { $0 >= firstDay && $0 <= now }
        let loggedWorkoutDays = Set(finished.map { calendar.startOfDay(for: $0) })
        let days = (0 ..< Self.weekCount * 7).compactMap { offset -> Day? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
                return nil
            }
            let day = calendar.startOfDay(for: date)
            return Day(
                date: day,
                hasLoggedWorkout: loggedWorkoutDays.contains(day),
                isToday: day == today,
                isAfterToday: day > today,
            )
        }
        self.firstDay = firstDay
        weeks = stride(from: 0, to: days.count, by: 7).map { start in
            Array(days[start ..< min(start + 7, days.count)])
        }
        loggedWorkoutCount = finished.count
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
