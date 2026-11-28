import Foundation
@testable import WorkoutStore

/// Finished workouts built by hand for Log's readings: a fixed calendar, time zone, and locale,
/// and a `now` of Saturday, November 21, 2026, 6 pm in New York.
enum LogFixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }()

    static let locale = Locale(identifier: "en_US")

    static let now = date(day: 21, hour: 18)

    static let row = UUID()

    static func date(day: Int, hour: Int = 10, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: day,
            hour: hour,
            minute: minute,
        )) ?? .distantPast
    }

    static func set(
        _ exerciseID: String,
        round: Int = 1,
        _ target: SetTarget,
        _ weight: Weight? = nil,
        planned: SetTarget? = nil,
        side: Side? = nil,
        row: UUID = row,
        name: String? = "Name",
    ) -> LoggedSet {
        LoggedSet(
            row: row,
            exerciseID: exerciseID,
            exerciseName: name,
            round: round,
            side: side,
            target: target,
            weight: weight,
            plannedTarget: planned ?? target,
            plannedWeight: weight,
            loggedAt: now,
        )
    }

    /// A logged workout of 51 minutes, finished `daysAgo` calendar days before `now` at 11 am.
    static func loggedWorkout(
        daysAgo: Int,
        _ sets: [LoggedSet],
        name: String = "Upper",
    ) -> WorkoutSession {
        let end = calendar.date(byAdding: .day, value: -daysAgo, to: date(day: 21, hour: 11))
            ?? .distantPast
        return WorkoutSession(
            workoutID: UUID(),
            workoutName: name,
            startedAt: end.addingTimeInterval(-51 * 60),
            endedAt: end,
            sets: sets,
        )
    }

    static func pounds(_ amount: Double) -> Weight {
        Weight(amount, .pounds)
    }
}
