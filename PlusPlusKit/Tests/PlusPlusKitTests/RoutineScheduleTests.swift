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

    @Test func weekdaysMissedDayCarriesOverAsMissed() {
        // Mon/Thu schedule, completed Monday, Thursday missed: on Saturday
        // (not itself a scheduled day) it reads as a gentle carried MISS,
        // not the green due — and `since` / dueSince point at Thursday.
        let schedule = RoutineSchedule.weekdays([2, 5])
        let saturday = date(2026, 7, 11)
        let monday = date(2026, 7, 6)
        let thursday = calendar.startOfDay(for: date(2026, 7, 9))
        #expect(schedule.dueState(lastCompleted: monday, today: saturday, calendar: calendar) == .missed(since: thursday))
        #expect(schedule.dueSince(lastCompleted: monday, today: saturday, calendar: calendar) == thursday)
    }

    @Test func weekdaysCarriedOverDueIsSatisfiedByLateCompletion() {
        // Completing the missed Thursday on Saturday satisfies that
        // occurrence and ONLY that occurrence — one workout, one
        // occurrence (Dave's #267 ruling): the routine WAS carried-due
        // on Saturday (previous completion Monday, Thursday missed), so
        // the session is a make-up, not an extra, and Monday stays the
        // next occurrence.
        let schedule = RoutineSchedule.weekdays([2, 5])
        let sunday = date(2026, 7, 12)
        let state = schedule.dueState(
            lastCompleted: date(2026, 7, 11),
            previousCompleted: date(2026, 7, 6),
            today: sunday,
            calendar: calendar
        )
        #expect(state == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 13))))
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

    @Test func recurrenceLabelReadsAsAnOngoingPattern() {
        // Fixed days lead with "every" — the recurrence the "beyond this
        // week" summary must convey so a single Saturday card beside it
        // doesn't read as a duplicate.
        #expect(RoutineSchedule.weekdays([7]).recurrenceLabel == "every sat")
        #expect(RoutineSchedule.weekdays([5, 2]).recurrenceLabel == "every mon/thu")
        // Frequency reads as a rate that never names a weekday — the cue
        // that tells a rolling cadence apart from fixed days at a glance.
        #expect(RoutineSchedule.frequency(times: 1, perDays: 1).recurrenceLabel == "daily")
        #expect(RoutineSchedule.frequency(times: 1, perDays: 7).recurrenceLabel == "weekly")
        #expect(RoutineSchedule.frequency(times: 1, perDays: 2).recurrenceLabel == "every 2d")
        #expect(RoutineSchedule.frequency(times: 3, perDays: 7).recurrenceLabel == "3×/wk")
        #expect(RoutineSchedule.frequency(times: 2, perDays: 1).recurrenceLabel == "2×/day")
        #expect(RoutineSchedule.frequency(times: 3, perDays: 10).recurrenceLabel == "3×/10d")
        #expect(RoutineSchedule.unscheduled.recurrenceLabel == "anytime")
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
        // Mondays only, on pace (previous completion satisfied its
        // Monday), then an EXTRA session on Wednesday: nothing was
        // outstanding that day, so it banks the upcoming Monday — not
        // due that day, and next points a further week out.
        let schedule = RoutineSchedule.weekdays([2])
        let wednesday = date(2026, 7, 8)
        let state = schedule.dueState(
            lastCompleted: wednesday,
            previousCompleted: date(2026, 7, 6),
            today: date(2026, 7, 13),
            calendar: calendar
        )
        #expect(state == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 20))))
    }

    @Test func weekdaysLateMakeUpDoesNotBankTheNextOccurrence() {
        // Mon/Thu, Thursday missed, made up on Saturday: the routine
        // was carried-due when that session happened, so it discharges
        // Thursday and ONLY Thursday — Monday still arrives due, and
        // the week ahead still lists it.
        let schedule = RoutineSchedule.weekdays([2, 5])
        let madeUpSaturday = date(2026, 7, 11)
        let previousMonday = date(2026, 7, 6)
        #expect(schedule.dueState(
            lastCompleted: madeUpSaturday,
            previousCompleted: previousMonday,
            today: date(2026, 7, 13),
            calendar: calendar
        ) == .due)
        #expect(schedule.upcomingScheduledDays(
            lastCompleted: madeUpSaturday,
            previousCompleted: previousMonday,
            today: date(2026, 7, 12),
            calendar: calendar
        ) == [calendar.startOfDay(for: date(2026, 7, 13)), calendar.startOfDay(for: date(2026, 7, 16))])
    }

    @Test func weekdaysFirstEverCompletionOnAnOffDayDoesNotBank() {
        // No previous completion: a never-done routine reads as due
        // every day, so the first session — whatever day it lands on —
        // discharges that standing due-ness rather than banking the
        // next occurrence (the conservative nil cutoff).
        let schedule = RoutineSchedule.weekdays([2])
        let wednesday = date(2026, 7, 8)
        #expect(schedule.dueState(lastCompleted: wednesday, today: date(2026, 7, 13), calendar: calendar) == .due)
    }

    @Test func weekdaysEarlyCompletionSatisfiesOnlyOneOccurrence() {
        // Mon/Thu, Monday done on time, an extra session Tuesday:
        // Thursday is banked, the Monday after is not — one workout,
        // one occurrence.
        let schedule = RoutineSchedule.weekdays([2, 5])
        let tuesday = date(2026, 7, 7)
        let previousMonday = date(2026, 7, 6)
        #expect(schedule.dueState(lastCompleted: tuesday, previousCompleted: previousMonday, today: date(2026, 7, 9), calendar: calendar)
                == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 13))))
        #expect(schedule.dueState(lastCompleted: tuesday, previousCompleted: previousMonday, today: date(2026, 7, 13), calendar: calendar) == .due)
    }

    @Test func weekdaysCompletionOnAScheduledDayDoesNotBankTheNext() {
        // The window's lower bound is exclusive: Monday's on-schedule
        // session satisfies Monday only, and Thursday still arrives
        // due — however clean the history before it.
        let schedule = RoutineSchedule.weekdays([2, 5])
        let monday = date(2026, 7, 6)
        #expect(schedule.dueState(
            lastCompleted: monday,
            previousCompleted: date(2026, 7, 2),
            today: date(2026, 7, 9),
            calendar: calendar
        ) == .due)
    }

    @Test func dueSinceSkipsAnOccurrenceSatisfiedEarly() {
        // Mon/Thu on pace, an extra Wednesday session (banking
        // Thursday), today the next Monday: due-ness began Monday, not
        // the banked Thursday.
        let schedule = RoutineSchedule.weekdays([2, 5])
        let wednesday = date(2026, 7, 8)
        let previousMonday = date(2026, 7, 6)
        let monday = date(2026, 7, 13)
        #expect(schedule.dueState(lastCompleted: wednesday, previousCompleted: previousMonday, today: monday, calendar: calendar) == .due)
        #expect(schedule.dueSince(lastCompleted: wednesday, previousCompleted: previousMonday, today: monday, calendar: calendar)
                == calendar.startOfDay(for: monday))
    }

    @Test func frequencyIgnoresPreviousCompleted() {
        // Frequency anchors to the last completion; the deeper history
        // changes nothing.
        let schedule = RoutineSchedule.frequency(times: 1, perDays: 7)
        let completed = date(2026, 7, 8)
        let today = date(2026, 7, 9)
        let bare = schedule.dueState(lastCompleted: completed, today: today, calendar: calendar)
        let threaded = schedule.dueState(
            lastCompleted: completed,
            previousCompleted: date(2026, 7, 6),
            today: today,
            calendar: calendar
        )
        #expect(bare == threaded)
        #expect(threaded == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 15))))
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
        // Mondays only, on pace, an extra Wednesday session: the
        // banked Monday is not an upcoming day — within 7 days nothing
        // remains, and a wider horizon shows the Monday after.
        let schedule = RoutineSchedule.weekdays([2])
        let wednesday = date(2026, 7, 8)
        let previousMonday = date(2026, 7, 6)
        let thursday = date(2026, 7, 9)
        #expect(schedule.upcomingScheduledDays(
            lastCompleted: wednesday, previousCompleted: previousMonday, today: thursday, calendar: calendar
        ).isEmpty)
        #expect(schedule.upcomingScheduledDays(
            lastCompleted: wednesday, previousCompleted: previousMonday, today: thursday, horizon: 14, calendar: calendar
        ) == [calendar.startOfDay(for: date(2026, 7, 20))])
    }

    @Test func upcomingDaysNeverRepeatACarriedOverDay() {
        // Thursdays only, last done ON a Thursday, the next one missed:
        // Friday's carried due-ness is today's business — upcoming
        // holds ONLY the next real occurrence, no phantom Friday or
        // Saturday entries from the carried tail.
        let schedule = RoutineSchedule.weekdays([5])
        let completedThursday = date(2026, 7, 2)
        let friday = date(2026, 7, 10)
        // Friday isn't a Thursday, so the missed Thursday reads as a carry.
        #expect(schedule.dueState(lastCompleted: completedThursday, today: friday, calendar: calendar)
                == .missed(since: calendar.startOfDay(for: date(2026, 7, 9))))
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

    // MARK: - Missed vs due, and the added-to-library anchor (2026-07-14)

    @Test func dueSinceIsTodayWhenTodayWinsOverAnEarlierMiss() {
        // Mon/Thu, never done: on Thursday, today is a scheduled unmet day
        // (`.due`) AND Monday also went unmet. "Today wins", so due-ness
        // began TODAY, not the older Monday lapse.
        let schedule = RoutineSchedule.weekdays([2, 5])
        let thursday = date(2026, 7, 9)
        #expect(schedule.dueState(lastCompleted: nil, today: thursday, calendar: calendar) == .due)
        #expect(schedule.dueSince(lastCompleted: nil, today: thursday, calendar: calendar)
                == calendar.startOfDay(for: thursday))
    }

    @Test func weekdaysScheduledTodayIsDueNotMissed() {
        // Tuesdays only, never done, today IS Tuesday: the green due, and
        // never a miss — today's occurrence outranks any carry.
        let schedule = RoutineSchedule.weekdays([3])
        let tuesday = date(2026, 7, 14)
        #expect(schedule.dueState(lastCompleted: nil, today: tuesday, calendar: calendar) == .due)
    }

    @Test func weekdaysMissedShowsAsMissedTheDayAfter() {
        // Tuesdays only, never done, today is Wednesday: last Tuesday went
        // unmet and today isn't scheduled, so it's a gentle carried miss.
        let schedule = RoutineSchedule.weekdays([3])
        let wednesday = date(2026, 7, 15)
        #expect(schedule.dueState(lastCompleted: nil, today: wednesday, calendar: calendar)
                == .missed(since: calendar.startOfDay(for: date(2026, 7, 14))))
    }

    @Test func weekdaysTodayWinsOverAnEarlierMissThisWeek() {
        // Mon/Thu, never done (Monday missed), today Thursday: today is a
        // scheduled unmet day, so it reads as due — not "missed since Mon".
        let schedule = RoutineSchedule.weekdays([2, 5])
        let thursday = date(2026, 7, 9)
        #expect(schedule.dueState(lastCompleted: nil, today: thursday, calendar: calendar) == .due)
    }

    @Test func weekdaysAddedAfterALapsedOccurrenceIsNotMissed() {
        // THE BUG (2026-07-14): a Tuesday routine added Sunday, viewed the
        // following Monday, must NOT read as overdue from the Tuesday it
        // was never around for — it's simply not due, next Tuesday ahead.
        let schedule = RoutineSchedule.weekdays([3]) // Tuesdays
        let addedSunday = date(2026, 7, 12)
        let monday = date(2026, 7, 13)
        let state = schedule.dueState(lastCompleted: nil, today: monday, addedOn: addedSunday, calendar: calendar)
        #expect(state == .notDue(nextDue: calendar.startOfDay(for: date(2026, 7, 14))))
    }

    @Test func weekdaysAddedBeforeALapsedOccurrenceStaysMissed() {
        // Same Tuesday routine, but it joined the library two weeks back —
        // last Tuesday was a real miss and carries as such.
        let schedule = RoutineSchedule.weekdays([3])
        let addedLongAgo = date(2026, 7, 1)
        let monday = date(2026, 7, 13)
        let state = schedule.dueState(lastCompleted: nil, today: monday, addedOn: addedLongAgo, calendar: calendar)
        #expect(state == .missed(since: calendar.startOfDay(for: date(2026, 7, 7))))
    }

    @Test func weekdaysAddedTodayOnItsScheduledDayIsDue() {
        // Added on a Tuesday that is also its scheduled day: due today, the
        // anchor's boundary is inclusive.
        let schedule = RoutineSchedule.weekdays([3])
        let tuesday = date(2026, 7, 14)
        #expect(schedule.dueState(lastCompleted: nil, today: tuesday, addedOn: tuesday, calendar: calendar) == .due)
    }

    @Test func upcomingRespectsTheAddedAnchor() {
        // A routine added today still previews its future occurrences —
        // the anchor only silences the PAST, never the week ahead.
        let schedule = RoutineSchedule.weekdays([3]) // Tuesdays
        let monday = date(2026, 7, 13)
        let days = schedule.upcomingScheduledDays(lastCompleted: nil, today: monday, addedOn: monday, calendar: calendar)
        #expect(days == [calendar.startOfDay(for: date(2026, 7, 14))])
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

    // MARK: - Weekly expectation (the week block bar)

    @Test func expectedSessionsPerWeekCountsWeekdays() {
        #expect(RoutineSchedule.unscheduled.expectedSessionsPerWeek == 0)
        #expect(RoutineSchedule.weekdays([]).expectedSessionsPerWeek == 0)
        #expect(RoutineSchedule.weekdays([2, 4, 6]).expectedSessionsPerWeek == 3)
    }

    @Test func expectedSessionsPerWeekNormalizesFrequencyToSevenDays() {
        #expect(RoutineSchedule.frequency(times: 3, perDays: 7).expectedSessionsPerWeek == 3)
        #expect(RoutineSchedule.frequency(times: 1, perDays: 2).expectedSessionsPerWeek == 4)
        // A schedule that exists never rounds to zero.
        #expect(RoutineSchedule.frequency(times: 1, perDays: 10).expectedSessionsPerWeek == 1)
        #expect(RoutineSchedule.frequency(times: 2, perDays: 7).expectedSessionsPerWeek == 2)
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
