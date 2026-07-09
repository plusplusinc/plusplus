import Foundation
import Testing
@testable import PlusPlusKit

@Suite("RoutineSchedule")
struct RoutineScheduleTests {
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
        let schedule = RoutineSchedule.weekdays([2, 4, 6]) // Mon/Wed/Fri
        let monday = date(2026, 7, 6)
        #expect(schedule.dueState(lastCompleted: nil, today: monday, calendar: calendar) == .due)
    }

    @Test func weekdaysNotDueOnARestDayPointsAtNextScheduledDay() {
        let schedule = RoutineSchedule.weekdays([2, 4, 6])
        let tuesday = date(2026, 7, 7)
        // Monday was completed, so Tuesday is a clean rest day.
        let state = schedule.dueState(lastCompleted: date(2026, 7, 6), today: tuesday, calendar: calendar)
        #expect(state == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 8))))
    }

    @Test func weekdaysMissedDayCarriesOverAsDue() {
        // Mon/Thu schedule, completed Monday, Thursday missed: still due
        // on Saturday, and dueSince points at Thursday.
        let schedule = RoutineSchedule.weekdays([2, 5])
        let saturday = date(2026, 7, 11)
        let monday = date(2026, 7, 6)
        #expect(schedule.dueState(lastCompleted: monday, today: saturday, calendar: calendar) == .due)
        #expect(schedule.dueSince(lastCompleted: monday, today: saturday, calendar: calendar)
                == calendar.startOfDay(for: date(2026, 7, 9)))
    }

    @Test func weekdaysCarriedOverDueIsSatisfiedByLateCompletion() {
        // Completing the missed Thursday on Saturday satisfies that
        // occurrence: Sunday is a rest day. Since #267 the Saturday
        // session also banks Monday's occurrence — it falls in Monday's
        // (thu, mon] window, and with a single lastCompleted a late
        // make-up and an early session are the same fact — so next
        // points past Monday at the Thursday after.
        let schedule = RoutineSchedule.weekdays([2, 5])
        let sunday = date(2026, 7, 12)
        let state = schedule.dueState(lastCompleted: date(2026, 7, 11), today: sunday, calendar: calendar)
        #expect(state == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 16))))
    }

    @Test func dueTodayHasTodayAsDueSince() {
        let schedule = RoutineSchedule.weekdays([2]) // Mondays
        let monday = date(2026, 7, 6)
        #expect(schedule.dueSince(lastCompleted: date(2026, 6, 29), today: monday, calendar: calendar)
                == calendar.startOfDay(for: monday))
    }

    @Test func overdueFrequencyDueSinceIsTheSlotBoundary() {
        let schedule = RoutineSchedule.frequency(times: 1, perDays: 7)
        let completed = date(2026, 6, 22)
        // Slot ended jun 29; on jul 6 it has been due since jun 29.
        #expect(schedule.dueSince(lastCompleted: completed, today: date(2026, 7, 6), calendar: calendar)
                == calendar.startOfDay(for: date(2026, 6, 29)))
    }

    @Test func shortLabelsForAllModes() {
        #expect(RoutineSchedule.weekdays([5, 2]).shortLabel == "mon/thu")
        #expect(RoutineSchedule.weekdays([1, 2]).shortLabel == "mon/sun")
        #expect(RoutineSchedule.frequency(times: 2, perDays: 7).shortLabel == "2×/7d")
        #expect(RoutineSchedule.unscheduled.shortLabel == "no schedule")
    }

    @Test func weekdaysCompletedTodaySatisfiesTheDay() {
        let schedule = RoutineSchedule.weekdays([2]) // Mondays only
        let monday = date(2026, 7, 6)
        let earlierToday = date(2026, 7, 6, hour: 7)
        let state = schedule.dueState(lastCompleted: earlierToday, today: monday, calendar: calendar)
        // Next due is next Monday, a full week out.
        #expect(state == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 13))))
    }

    @Test func weekdaysYesterdaysCompletionDoesNotSatisfyToday() {
        let schedule = RoutineSchedule.weekdays([2, 3]) // Mon + Tue
        let tuesday = date(2026, 7, 7)
        let monday = date(2026, 7, 6)
        #expect(schedule.dueState(lastCompleted: monday, today: tuesday, calendar: calendar) == .due)
    }

    // MARK: - Early completion (#267)

    @Test func weekdaysEarlyCompletionSatisfiesTheNextOccurrence() {
        // Mondays only, completed off-schedule on Wednesday: the
        // session banks the upcoming Monday — not due that day, and
        // next points a further week out.
        let schedule = RoutineSchedule.weekdays([2])
        let wednesday = date(2026, 7, 8)
        let state = schedule.dueState(lastCompleted: wednesday, today: date(2026, 7, 13), calendar: calendar)
        #expect(state == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 20))))
    }

    @Test func weekdaysEarlyCompletionSatisfiesOnlyOneOccurrence() {
        // Mon/Thu, completed Tuesday: Thursday is banked, the Monday
        // after is not — one satisfaction per inter-occurrence window.
        let schedule = RoutineSchedule.weekdays([2, 5])
        let tuesday = date(2026, 7, 7)
        #expect(schedule.dueState(lastCompleted: tuesday, today: date(2026, 7, 9), calendar: calendar)
                == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 13))))
        #expect(schedule.dueState(lastCompleted: tuesday, today: date(2026, 7, 13), calendar: calendar) == .due)
    }

    @Test func weekdaysCompletionOnAScheduledDayDoesNotBankTheNext() {
        // The window's lower bound is exclusive: Monday's on-schedule
        // session satisfies Monday only, and Thursday still arrives due.
        let schedule = RoutineSchedule.weekdays([2, 5])
        let monday = date(2026, 7, 6)
        #expect(schedule.dueState(lastCompleted: monday, today: date(2026, 7, 9), calendar: calendar) == .due)
    }

    @Test func dueSinceSkipsAnOccurrenceSatisfiedEarly() {
        // Mon/Thu, completed Wednesday (banking Thursday), today the
        // next Monday: due-ness began Monday, not the banked Thursday.
        let schedule = RoutineSchedule.weekdays([2, 5])
        let wednesday = date(2026, 7, 8)
        let monday = date(2026, 7, 13)
        #expect(schedule.dueState(lastCompleted: wednesday, today: monday, calendar: calendar) == .due)
        #expect(schedule.dueSince(lastCompleted: wednesday, today: monday, calendar: calendar)
                == calendar.startOfDay(for: monday))
    }

    // MARK: - Upcoming scheduled days (#267)

    @Test func upcomingDaysListAWeekOfWeekdayOccurrences() {
        // Mon/Wed/Fri, completed on Monday: the next 7 days hold Wed,
        // Fri, and the following Monday (today + 7, the inclusive
        // horizon edge).
        let schedule = RoutineSchedule.weekdays([2, 4, 6])
        let monday = date(2026, 7, 6)
        let days = schedule.upcomingScheduledDays(lastCompleted: monday, today: monday, calendar: calendar)
        #expect(days == [
            calendar.startOfDay(for: date(2026, 7, 8)),
            calendar.startOfDay(for: date(2026, 7, 10)),
            calendar.startOfDay(for: date(2026, 7, 13)),
        ])
    }

    @Test func upcomingDaysOmitAnOccurrenceSatisfiedEarly() {
        // Mondays only, completed Wednesday: the banked Monday is not
        // an upcoming day — within 7 days nothing remains, and a wider
        // horizon shows the Monday after.
        let schedule = RoutineSchedule.weekdays([2])
        let wednesday = date(2026, 7, 8)
        let thursday = date(2026, 7, 9)
        #expect(schedule.upcomingScheduledDays(lastCompleted: wednesday, today: thursday, calendar: calendar).isEmpty)
        #expect(schedule.upcomingScheduledDays(lastCompleted: wednesday, today: thursday, horizon: 14, calendar: calendar)
                == [calendar.startOfDay(for: date(2026, 7, 20))])
    }

    @Test func upcomingDaysNeverRepeatACarriedOverDay() {
        // Thursdays only, last done ON a Thursday, the next one missed:
        // Friday's carried due-ness is today's business — upcoming
        // holds ONLY the next real occurrence, no phantom Friday or
        // Saturday entries from the carried tail.
        let schedule = RoutineSchedule.weekdays([5])
        let completedThursday = date(2026, 7, 2)
        let friday = date(2026, 7, 10)
        #expect(schedule.dueState(lastCompleted: completedThursday, today: friday, calendar: calendar) == .due)
        let days = schedule.upcomingScheduledDays(lastCompleted: completedThursday, today: friday, calendar: calendar)
        #expect(days == [calendar.startOfDay(for: date(2026, 7, 16))])
    }

    @Test func upcomingDaysRespectTheHorizon() {
        // Mon/Thu from Saturday (carried-due, which never blocks the
        // preview): the full week shows Monday and Thursday, a 2-day
        // horizon clips to Monday, a zero horizon holds nothing.
        let schedule = RoutineSchedule.weekdays([2, 5])
        let completedMonday = date(2026, 7, 6)
        let saturday = date(2026, 7, 11)
        #expect(schedule.upcomingScheduledDays(lastCompleted: completedMonday, today: saturday, calendar: calendar)
                == [calendar.startOfDay(for: date(2026, 7, 13)), calendar.startOfDay(for: date(2026, 7, 16))])
        #expect(schedule.upcomingScheduledDays(lastCompleted: completedMonday, today: saturday, horizon: 2, calendar: calendar)
                == [calendar.startOfDay(for: date(2026, 7, 13))])
        #expect(schedule.upcomingScheduledDays(lastCompleted: completedMonday, today: saturday, horizon: 0, calendar: calendar).isEmpty)
    }

    @Test func upcomingDaysForFrequencyPredictTheSingleNextDay() {
        // 1× per 7 days, completed Monday: one predicted day, a week
        // out from the anchor.
        let schedule = RoutineSchedule.frequency(times: 1, perDays: 7)
        let monday = date(2026, 7, 6)
        let days = schedule.upcomingScheduledDays(lastCompleted: monday, today: date(2026, 7, 8), calendar: calendar)
        #expect(days == [calendar.startOfDay(for: date(2026, 7, 13))])
    }

    @Test func upcomingDaysForFrequencyClipAtTheHorizon() {
        // A predicted day beyond the horizon stays out — the cadence
        // summary line covers "beyond this week".
        let schedule = RoutineSchedule.frequency(times: 1, perDays: 10)
        let monday = date(2026, 7, 6)
        #expect(schedule.upcomingScheduledDays(lastCompleted: monday, today: date(2026, 7, 7), calendar: calendar).isEmpty)
    }

    @Test func upcomingDaysForFrequencyDueTodayAreEmpty() {
        // Due now (never done, or overdue) is today's business — the
        // carried tail never previews as future days.
        let schedule = RoutineSchedule.frequency(times: 1, perDays: 7)
        #expect(schedule.upcomingScheduledDays(lastCompleted: nil, today: date(2026, 7, 6), calendar: calendar).isEmpty)
        #expect(schedule.upcomingScheduledDays(lastCompleted: date(2026, 6, 1), today: date(2026, 7, 6), calendar: calendar).isEmpty)
    }

    @Test func upcomingDaysForUnscheduledAreEmpty() {
        let days = RoutineSchedule.unscheduled.upcomingScheduledDays(lastCompleted: nil, today: date(2026, 7, 6), calendar: calendar)
        #expect(days.isEmpty)
    }

    @Test func frequencyEarlyCompletionPushesTheNextDueDate() {
        // Frequency anchors to the last completion, so an early session
        // re-anchors the slot on its own — no weekday-style window
        // needed. On pace (completed Jul 6), the next slot opens Jul 13…
        let schedule = RoutineSchedule.frequency(times: 1, perDays: 7)
        #expect(schedule.dueState(lastCompleted: date(2026, 7, 6), today: date(2026, 7, 8), calendar: calendar)
                == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 13))))
        // …an early make-up on Jul 8 pushes it to Jul 15.
        #expect(schedule.dueState(lastCompleted: date(2026, 7, 8), today: date(2026, 7, 9), calendar: calendar)
                == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 15))))
    }

    // MARK: - Frequency

    @Test func frequencyNeverDoneIsDue() {
        let schedule = RoutineSchedule.frequency(times: 3, perDays: 7)
        #expect(schedule.dueState(lastCompleted: nil, today: date(2026, 7, 6), calendar: calendar) == .due)
    }

    @Test func frequencyCompletedTodayIsNotDue() {
        let schedule = RoutineSchedule.frequency(times: 3, perDays: 7)
        let today = date(2026, 7, 6)
        let state = schedule.dueState(lastCompleted: date(2026, 7, 6, hour: 8), today: today, calendar: calendar)
        // ceil(7/3) = 3 days out from the completion.
        #expect(state == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 9))))
    }

    @Test func frequencyUsesRationalSlotsNotRoundedIntervals() {
        // 3× per 7 days: due when daysSince × 3 ≥ 7, i.e. from day 3
        // after a completion (2 × 3 = 6 < 7; 3 × 3 = 9 ≥ 7).
        let schedule = RoutineSchedule.frequency(times: 3, perDays: 7)
        let completed = date(2026, 7, 6)
        #expect(schedule.dueState(lastCompleted: completed, today: date(2026, 7, 8), calendar: calendar)
                != .due)
        #expect(schedule.dueState(lastCompleted: completed, today: date(2026, 7, 9), calendar: calendar)
                == .due)
    }

    @Test func frequencyDailyIsDueTheNextDay() {
        let schedule = RoutineSchedule.frequency(times: 1, perDays: 1)
        let completed = date(2026, 7, 6)
        #expect(schedule.dueState(lastCompleted: completed, today: date(2026, 7, 6, hour: 22), calendar: calendar)
                == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 7))))
        #expect(schedule.dueState(lastCompleted: completed, today: date(2026, 7, 7), calendar: calendar) == .due)
    }

    @Test func frequencyOverdueStaysDue() {
        let schedule = RoutineSchedule.frequency(times: 1, perDays: 7)
        let completed = date(2026, 6, 1)
        #expect(schedule.dueState(lastCompleted: completed, today: date(2026, 7, 6), calendar: calendar) == .due)
    }

    // MARK: - Unscheduled + normalization

    @Test func unscheduledHasNoDueState() {
        let schedule = RoutineSchedule.unscheduled
        #expect(schedule.dueState(lastCompleted: nil, today: date(2026, 7, 6), calendar: calendar) == .unscheduled)
    }

    @Test func emptyOrInvalidWeekdaysNormalizeToUnscheduled() {
        #expect(RoutineSchedule.weekdays([]).normalized == .unscheduled)
        #expect(RoutineSchedule.weekdays([0, 8]).normalized == .unscheduled)
        #expect(RoutineSchedule.weekdays([0, 2, 8]).normalized == .weekdays([2]))
    }

    @Test func frequencyCountsClampToAtLeastOne() {
        #expect(RoutineSchedule.frequency(times: 0, perDays: -3).normalized
                == .frequency(times: 1, perDays: 1))
    }

    // MARK: - Codable

    @Test func codableRoundTripsAllModes() throws {
        let schedules: [RoutineSchedule] = [
            .unscheduled,
            .weekdays([2, 4, 6]),
            .frequency(times: 3, perDays: 7),
        ]
        for schedule in schedules {
            let data = try JSONEncoder().encode(schedule)
            let decoded = try JSONDecoder().decode(RoutineSchedule.self, from: data)
            #expect(decoded == schedule)
        }
    }

    @Test func decodingNormalizes() throws {
        let json = #"{"mode":"weekdays","weekdays":[0,3,9]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RoutineSchedule.self, from: json)
        #expect(decoded == .weekdays([3]))
    }

    @Test func encodedWeekdaysAreSortedForStableJSON() throws {
        let data = try JSONEncoder().encode(RoutineSchedule.weekdays([6, 2, 4]))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#"[2,4,6]"#))
    }
}
