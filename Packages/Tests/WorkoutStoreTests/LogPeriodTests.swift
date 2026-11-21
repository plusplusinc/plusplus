import Foundation
import Testing
@testable import WorkoutStore

@Suite("The period: four calendar weeks ending with this week, a day per square")
struct LogPeriodTests {
    private typealias Fixture = LogFixture

    private static func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Fixture.calendar
        calendar.firstWeekday = firstWeekday
        calendar.locale = Fixture.locale
        return calendar
    }

    private static let sundayFirst = calendar(firstWeekday: 1)
    private static let mondayFirst = calendar(firstWeekday: 2)

    private func period(_ workouts: [Workout] = [], calendar: Calendar = sundayFirst) -> LogPeriod {
        LogPeriod(workouts: workouts, calendar: calendar, now: Fixture.now)
    }

    @Test("A week that starts on Sunday: Sun Oct 25 to Sat Nov 21, today the last square")
    func sundayWeeks() throws {
        let period = period()
        #expect(period.firstDayText(locale: Fixture.locale, calendar: Self.sundayFirst)
            == "Oct 25")
        #expect(period.weeks.count == 4)
        #expect(period.weeks.allSatisfy { $0.count == 7 })
        let last = try #require(period.weeks.last?.last)
        #expect(last.isToday)
        #expect(period.weeks.joined().allSatisfy { !$0.isAfterToday })
        #expect(LogPeriod.weekdayInitials(calendar: Self.sundayFirst)
            == ["S", "M", "T", "W", "T", "F", "S"])
    }

    @Test("A week that starts on Monday: Mon Oct 26 to Sun Nov 22, Sunday after today")
    func mondayWeeks() {
        let period = period(calendar: Self.mondayFirst)
        #expect(period.firstDayText(locale: Fixture.locale, calendar: Self.mondayFirst)
            == "Oct 26")
        let lastWeek = period.weeks.last ?? []
        #expect(lastWeek.map(\.isToday) == [false, false, false, false, false, true, false])
        #expect(lastWeek.map(\.isAfterToday) == [false, false, false, false, false, false, true])
        #expect(LogPeriod.weekdayInitials(calendar: Self.mondayFirst)
            == ["M", "T", "W", "T", "F", "S", "S"])
    }

    @Test("A workout finished at 11:59 pm marks its day; one before the first day is out")
    func beforeMidnight() {
        let late = Workout(
            routineID: UUID(),
            routineName: "Late",
            startedAt: Fixture.date(day: 20, hour: 23),
            endedAt: Fixture.date(day: 20, hour: 23, minute: 59),
        )
        let before = Fixture.workout(daysAgo: 28, [])
        let period = period([late, before])
        let marked = period.weeks.joined().filter(\.hasWorkout).map(\.date)
        #expect(marked == [Fixture.calendar.startOfDay(for: Fixture.date(day: 20))])
        #expect(period.workoutCount == 1)
        #expect(period.workoutCountText(locale: Fixture.locale) == "1 workout")
    }

    @Test("Two workouts on one day mark one square and count two; one in progress counts none")
    func countsWorkouts() {
        let inProgress = Workout(routineID: UUID(), routineName: "Now", startedAt: Fixture.now)
        let period = period([
            Fixture.workout(daysAgo: 2, []),
            Fixture.workout(daysAgo: 2, []),
            inProgress,
        ])
        #expect(period.weeks.joined().filter(\.hasWorkout).count == 1)
        #expect(period.workoutCount == 2)
    }

    @Test("A day reads its date and whether a workout was done")
    func spokenDay() throws {
        let period = period([Fixture.workout(daysAgo: 0, [])])
        let today = try #require(period.weeks.last?.last)
        let yesterday = try #require(period.weeks.last?.dropLast().last)
        #expect(LogPeriod.spokenDay(today, locale: Fixture.locale, calendar: Self.sundayFirst)
            == "Today, Saturday, November 21, workout")
        #expect(LogPeriod.spokenDay(yesterday, locale: Fixture.locale, calendar: Self.sundayFirst)
            == "Friday, November 20, no workout")
    }
}
