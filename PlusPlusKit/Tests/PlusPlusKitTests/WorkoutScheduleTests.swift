import Foundation
import Testing
@testable import PlusPlusKit

@Suite("WorkoutSchedule")
struct WorkoutScheduleTests {
    // A fixed calendar so results don't depend on the machine's locale
    // or timezone. Gregorian + UTC; weekday numbers are 1 = Sunday.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-07-06 is a Monday (weekday 2).
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        DateComponents(calendar: calendar, year: year, month: month, day: day, hour: hour).date!
    }

    // MARK: - Weekdays

    @Test func weekdaysDueOnAScheduledDay() {
        let schedule = WorkoutSchedule.weekdays([2, 4, 6]) // Mon/Wed/Fri
        let monday = date(2026, 7, 6)
        #expect(schedule.dueState(lastCompleted: nil, today: monday, calendar: calendar) == .due)
    }

    @Test func weekdaysNotDueOnARestDayPointsAtNextScheduledDay() {
        let schedule = WorkoutSchedule.weekdays([2, 4, 6])
        let tuesday = date(2026, 7, 7)
        // Monday was completed, so Tuesday is a clean rest day.
        let state = schedule.dueState(lastCompleted: date(2026, 7, 6), today: tuesday, calendar: calendar)
        #expect(state == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 8))))
    }

    @Test func weekdaysMissedDayCarriesOverAsDue() {
        // Mon/Thu schedule, completed Monday, Thursday missed: still due
        // on Saturday, and dueSince points at Thursday.
        let schedule = WorkoutSchedule.weekdays([2, 5])
        let saturday = date(2026, 7, 11)
        let monday = date(2026, 7, 6)
        #expect(schedule.dueState(lastCompleted: monday, today: saturday, calendar: calendar) == .due)
        #expect(schedule.dueSince(lastCompleted: monday, today: saturday, calendar: calendar)
                == calendar.startOfDay(for: date(2026, 7, 9)))
    }

    @Test func weekdaysCarriedOverDueIsSatisfiedByLateCompletion() {
        // Completing the missed Thursday on Saturday satisfies that
        // occurrence: Sunday is a rest day pointing at Monday.
        let schedule = WorkoutSchedule.weekdays([2, 5])
        let sunday = date(2026, 7, 12)
        let state = schedule.dueState(lastCompleted: date(2026, 7, 11), today: sunday, calendar: calendar)
        #expect(state == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 13))))
    }

    @Test func dueTodayHasTodayAsDueSince() {
        let schedule = WorkoutSchedule.weekdays([2]) // Mondays
        let monday = date(2026, 7, 6)
        #expect(schedule.dueSince(lastCompleted: date(2026, 6, 29), today: monday, calendar: calendar)
                == calendar.startOfDay(for: monday))
    }

    @Test func overdueFrequencyDueSinceIsTheSlotBoundary() {
        let schedule = WorkoutSchedule.frequency(times: 1, perDays: 7)
        let completed = date(2026, 6, 22)
        // Slot ended jun 29; on jul 6 it has been due since jun 29.
        #expect(schedule.dueSince(lastCompleted: completed, today: date(2026, 7, 6), calendar: calendar)
                == calendar.startOfDay(for: date(2026, 6, 29)))
    }

    @Test func shortLabelsForAllModes() {
        #expect(WorkoutSchedule.weekdays([5, 2]).shortLabel == "mon/thu")
        #expect(WorkoutSchedule.weekdays([1, 2]).shortLabel == "mon/sun")
        #expect(WorkoutSchedule.frequency(times: 2, perDays: 7).shortLabel == "2×/7d")
        #expect(WorkoutSchedule.unscheduled.shortLabel == "no schedule")
    }

    @Test func weekdaysCompletedTodaySatisfiesTheDay() {
        let schedule = WorkoutSchedule.weekdays([2]) // Mondays only
        let monday = date(2026, 7, 6)
        let earlierToday = date(2026, 7, 6, hour: 7)
        let state = schedule.dueState(lastCompleted: earlierToday, today: monday, calendar: calendar)
        // Next due is next Monday, a full week out.
        #expect(state == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 13))))
    }

    @Test func weekdaysYesterdaysCompletionDoesNotSatisfyToday() {
        let schedule = WorkoutSchedule.weekdays([2, 3]) // Mon + Tue
        let tuesday = date(2026, 7, 7)
        let monday = date(2026, 7, 6)
        #expect(schedule.dueState(lastCompleted: monday, today: tuesday, calendar: calendar) == .due)
    }

    // MARK: - Frequency

    @Test func frequencyNeverDoneIsDue() {
        let schedule = WorkoutSchedule.frequency(times: 3, perDays: 7)
        #expect(schedule.dueState(lastCompleted: nil, today: date(2026, 7, 6), calendar: calendar) == .due)
    }

    @Test func frequencyCompletedTodayIsNotDue() {
        let schedule = WorkoutSchedule.frequency(times: 3, perDays: 7)
        let today = date(2026, 7, 6)
        let state = schedule.dueState(lastCompleted: date(2026, 7, 6, hour: 8), today: today, calendar: calendar)
        // ceil(7/3) = 3 days out from the completion.
        #expect(state == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 9))))
    }

    @Test func frequencyUsesRationalSlotsNotRoundedIntervals() {
        // 3× per 7 days: due when daysSince × 3 ≥ 7, i.e. from day 3
        // after a completion (2 × 3 = 6 < 7; 3 × 3 = 9 ≥ 7).
        let schedule = WorkoutSchedule.frequency(times: 3, perDays: 7)
        let completed = date(2026, 7, 6)
        #expect(schedule.dueState(lastCompleted: completed, today: date(2026, 7, 8), calendar: calendar)
                != .due)
        #expect(schedule.dueState(lastCompleted: completed, today: date(2026, 7, 9), calendar: calendar)
                == .due)
    }

    @Test func frequencyDailyIsDueTheNextDay() {
        let schedule = WorkoutSchedule.frequency(times: 1, perDays: 1)
        let completed = date(2026, 7, 6)
        #expect(schedule.dueState(lastCompleted: completed, today: date(2026, 7, 6, hour: 22), calendar: calendar)
                == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 7))))
        #expect(schedule.dueState(lastCompleted: completed, today: date(2026, 7, 7), calendar: calendar) == .due)
    }

    @Test func frequencyOverdueStaysDue() {
        let schedule = WorkoutSchedule.frequency(times: 1, perDays: 7)
        let completed = date(2026, 6, 1)
        #expect(schedule.dueState(lastCompleted: completed, today: date(2026, 7, 6), calendar: calendar) == .due)
    }

    // MARK: - Unscheduled + normalization

    @Test func unscheduledHasNoDueState() {
        let schedule = WorkoutSchedule.unscheduled
        #expect(schedule.dueState(lastCompleted: nil, today: date(2026, 7, 6), calendar: calendar) == .unscheduled)
    }

    @Test func emptyOrInvalidWeekdaysNormalizeToUnscheduled() {
        #expect(WorkoutSchedule.weekdays([]).normalized == .unscheduled)
        #expect(WorkoutSchedule.weekdays([0, 8]).normalized == .unscheduled)
        #expect(WorkoutSchedule.weekdays([0, 2, 8]).normalized == .weekdays([2]))
    }

    @Test func frequencyCountsClampToAtLeastOne() {
        #expect(WorkoutSchedule.frequency(times: 0, perDays: -3).normalized
                == .frequency(times: 1, perDays: 1))
    }

    // MARK: - Codable

    @Test func codableRoundTripsAllModes() throws {
        let schedules: [WorkoutSchedule] = [
            .unscheduled,
            .weekdays([2, 4, 6]),
            .frequency(times: 3, perDays: 7),
        ]
        for schedule in schedules {
            let data = try JSONEncoder().encode(schedule)
            let decoded = try JSONDecoder().decode(WorkoutSchedule.self, from: data)
            #expect(decoded == schedule)
        }
    }

    @Test func decodingNormalizes() throws {
        let json = #"{"mode":"weekdays","weekdays":[0,3,9]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkoutSchedule.self, from: json)
        #expect(decoded == .weekdays([3]))
    }

    @Test func encodedWeekdaysAreSortedForStableJSON() throws {
        let data = try JSONEncoder().encode(WorkoutSchedule.weekdays([6, 2, 4]))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#"[2,4,6]"#))
    }
}
