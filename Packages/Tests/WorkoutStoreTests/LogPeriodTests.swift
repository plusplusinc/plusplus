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

    private func period(
        _ loggedWorkouts: [WorkoutSession] = [],
        calendar: Calendar = sundayFirst,
    ) -> LogPeriod {
        LogPeriod(loggedWorkouts: loggedWorkouts, calendar: calendar, now: Fixture.now)
    }

    @Test("A week that starts on Sunday: Sun Oct 25 to Sat Nov 21, today the last square")
    func sundayWeeks() throws {
        let period = period()
        #expect(period.rangeText(locale: Fixture.locale, calendar: Self.sundayFirst)
            == "Oct 25\u{2009}\u{2013}\u{2009}Nov 21")
        #expect(period.spokenRange(locale: Fixture.locale, calendar: Self.sundayFirst)
            == "October 25 to November 21")
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
        #expect(period.rangeText(locale: Fixture.locale, calendar: Self.mondayFirst)
            == "Oct 26\u{2009}\u{2013}\u{2009}Nov 21")
        let lastWeek = period.weeks.last ?? []
        #expect(lastWeek.map(\.isToday) == [false, false, false, false, false, true, false])
        #expect(lastWeek.map(\.isAfterToday) == [false, false, false, false, false, false, true])
        #expect(LogPeriod.weekdayInitials(calendar: Self.mondayFirst)
            == ["M", "T", "W", "T", "F", "S", "S"])
    }

    @Test("A workout finished at 11:59 pm marks its day; one before the first day is out")
    func beforeMidnight() {
        let late = WorkoutSession(
            workoutID: UUID(),
            workoutName: "Late",
            startedAt: Fixture.date(day: 20, hour: 23),
            endedAt: Fixture.date(day: 20, hour: 23, minute: 59),
        )
        let before = Fixture.loggedWorkout(daysAgo: 28, [])
        let period = period([late, before])
        let marked = period.weeks.joined().filter(\.hasWorkoutSession).map(\.date)
        #expect(marked == [Fixture.calendar.startOfDay(for: Fixture.date(day: 20))])
        #expect(period.loggedWorkoutCount == 1)
        #expect(period.loggedWorkoutCountText(locale: Fixture.locale) == "1 workout")
    }

    @Test("A workout across midnight marks the day it started, the day its row reads")
    func acrossMidnight() {
        let late = WorkoutSession(
            workoutID: UUID(),
            workoutName: "Late",
            startedAt: Fixture.date(day: 19, hour: 23, minute: 30),
            endedAt: Fixture.date(day: 20, hour: 0, minute: 40),
        )
        let period = period([late])
        let marked = period.weeks.joined().filter(\.hasWorkoutSession).map(\.date)
        #expect(marked == [Fixture.calendar.startOfDay(for: Fixture.date(day: 19))])
        #expect(late.logLine(locale: Fixture.locale, calendar: Fixture.calendar)
            .hasPrefix("Thu, Nov 19"))
    }

    @Test("Two workouts on one day mark one square and count two; one in progress counts none")
    func countsWorkoutSessions() {
        let inProgress = WorkoutSession(
            workoutID: UUID(),
            workoutName: "Now",
            startedAt: Fixture.now,
        )
        let period = period([
            Fixture.loggedWorkout(daysAgo: 2, []),
            Fixture.loggedWorkout(daysAgo: 2, []),
            inProgress,
        ])
        #expect(period.weeks.joined().filter(\.hasWorkoutSession).count == 1)
        #expect(period.loggedWorkoutCount == 2)
    }

    /// History leaves a workout just finished out until it comes in.
    @Test("A log leaving a workout out counts and marks without it; nil or a stranger, unchanged")
    func leavingOut() {
        let earlier = Fixture.loggedWorkout(daysAgo: 2, [])
        let today = Fixture.loggedWorkout(daysAgo: 0, [])
        let log = WorkoutLog(loggedWorkouts: [earlier, today])
        let without = log.leavingOut(today.id)
        #expect(without.loggedWorkouts == [earlier])
        let marked = period(without.loggedWorkouts).weeks.joined().filter(\.hasWorkoutSession)
        #expect(marked.count == 1, "today's square fills only once the workout comes in")
        #expect(period(without.loggedWorkouts).loggedWorkoutCount == 1)
        #expect(log.leavingOut(nil) == log)
        #expect(log.leavingOut(UUID()) == log)
        let first = WorkoutLog(loggedWorkouts: [today])
        #expect(first.leavingOut(today.id).loggedWorkouts.isEmpty, "the first ever leaves none")
    }

    @Test("The bar's range: one month shortened, a year on each side across one, each day numbered")
    func rangeAcrossMonthsAndYears() throws {
        func range(year: Int, month: Int, day: Int) -> LogPeriod {
            let now = Fixture.calendar.date(
                from: DateComponents(year: year, month: month, day: day, hour: 18),
            ) ?? .distantPast
            return LogPeriod(loggedWorkouts: [], calendar: Self.sundayFirst, now: now)
        }
        let dash = "\u{2009}\u{2013}\u{2009}"
        let oneMonth = range(year: 2026, month: 11, day: 28)
        #expect(oneMonth.rangeText(locale: Fixture.locale, calendar: Self.sundayFirst)
            == "Nov 1\(dash)28")
        let newYear = range(year: 2027, month: 1, day: 2)
        #expect(newYear.rangeText(locale: Fixture.locale, calendar: Self.sundayFirst)
            == "Dec 6, 2026\(dash)Jan 2, 2027")
        #expect(newYear.spokenRange(locale: Fixture.locale, calendar: Self.sundayFirst)
            == "December 6 to January 2")
        let first = try #require(oneMonth.weeks.first?.first)
        #expect(LogPeriod.dayNumber(first, locale: Fixture.locale, calendar: Self.sundayFirst)
            == "1")
    }

    @Test("A day reads its date and whether a workout was done")
    func spokenDay() throws {
        let period = period([Fixture.loggedWorkout(daysAgo: 0, [])])
        let today = try #require(period.weeks.last?.last)
        let yesterday = try #require(period.weeks.last?.dropLast().last)
        #expect(LogPeriod.spokenDay(today, locale: Fixture.locale, calendar: Self.sundayFirst)
            == "Today, Saturday, November 21, workout")
        #expect(LogPeriod.spokenDay(yesterday, locale: Fixture.locale, calendar: Self.sundayFirst)
            == "Friday, November 20, no workout")
    }
}
