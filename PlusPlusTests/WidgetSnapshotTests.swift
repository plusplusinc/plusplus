import Foundation
import Testing
import PlusPlusKit
@testable import PlusPlus

/// Snapshot freshness (#159): widgets and Siri compute due-ness and the
/// streak from the snapshot's carried schedules instead of trusting a
/// list frozen at the last app launch.
@Suite("Widget snapshot freshness")
struct WidgetSnapshotTests {
    /// UTC-pinned like RoutineScheduleTests, so results don't depend on
    /// the machine's timezone.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A fixed Monday noon; RoutineSchedule weekday numbers are
    /// Calendar's (1 = Sunday), so Monday is 2.
    private var monday: Date {
        calendar.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 7, day: 6, hour: 12))!
    }

    private func snapshot(scheduled: [WidgetSnapshot.ScheduledRoutine]?,
                          generatedAt: Date,
                          due: [WidgetSnapshot.DueRoutine] = [],
                          weeklyCounts: [Int] = [Int](repeating: 0, count: 12)) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: generatedAt,
            routineNames: scheduled?.map(\.name) ?? [],
            due: due,
            streakWeeks: WidgetSnapshot.streak(fromWeeklyCounts: weeklyCounts),
            weeklyCounts: weeklyCounts,
            scheduled: scheduled
        )
    }

    private func routine(_ name: String, schedule: RoutineSchedule, lastCompleted: Date? = nil, previousCompleted: Date? = nil) -> WidgetSnapshot.ScheduledRoutine {
        .init(
            name: name,
            exerciseCount: 5,
            scheduleData: try? JSONEncoder().encode(schedule),
            lastCompleted: lastCompleted,
            previousCompleted: previousCompleted
        )
    }

    @Test func dueListRollsForwardWithoutTheApp() throws {
        // Push on Mondays (never done → due, carried over, every day);
        // Pull on Wednesdays, last done the previous Wednesday (Jul 1) —
        // satisfied on Monday, on again when its day comes back around.
        let previousWednesday = calendar.date(byAdding: .day, value: -5, to: monday)!
        let snap = snapshot(
            scheduled: [
                routine("Push Day", schedule: .weekdays([2])),
                routine("Pull Day", schedule: .weekdays([4]), lastCompleted: previousWednesday),
            ],
            generatedAt: monday
        )

        let mondayList = snap.dueList(at: monday, calendar: calendar)
        #expect(mondayList.map(\.name) == ["Push Day"])

        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday)!
        let wednesdayList = snap.dueList(at: wednesday, calendar: calendar)
        #expect(Set(wednesdayList.map(\.name)) == ["Push Day", "Pull Day"])

        // Completing Push on Monday satisfies it until next Monday.
        let done = snapshot(
            scheduled: [routine("Push Day", schedule: .weekdays([2]), lastCompleted: monday)],
            generatedAt: monday
        )
        #expect(done.dueList(at: wednesday, calendar: calendar).isEmpty)
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday)!
        #expect(done.dueList(at: nextMonday, calendar: calendar).map(\.name) == ["Push Day"])
    }

    @Test func extraSessionBanksTheNextOccurrenceInTheWidgetToo() {
        // #267: an extra Wednesday session (the previous Monday done on
        // time) banks next Monday — the widget's roll-forward agrees
        // with the app because previousCompleted rides the snapshot.
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday)!
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday)!
        let banked = snapshot(
            scheduled: [routine("Push Day", schedule: .weekdays([2]), lastCompleted: wednesday, previousCompleted: monday)],
            generatedAt: wednesday
        )
        #expect(banked.dueList(at: nextMonday, calendar: calendar).isEmpty)

        // A snapshot without previousCompleted (written pre-#267)
        // stays conservative: the day still shows.
        let legacy = snapshot(
            scheduled: [routine("Push Day", schedule: .weekdays([2]), lastCompleted: wednesday)],
            generatedAt: wednesday
        )
        #expect(legacy.dueList(at: nextMonday, calendar: calendar).map(\.name) == ["Push Day"])
    }

    @Test func oldSnapshotsFallBackToTheFrozenList() {
        let frozen = [WidgetSnapshot.DueRoutine(name: "Legacy Day", caption: "mon", exerciseCount: 3)]
        let snap = snapshot(scheduled: nil, generatedAt: monday, due: frozen)
        #expect(snap.dueList(at: monday, calendar: calendar).map(\.name) == ["Legacy Day"])
    }

    @Test func staleStreakRollsToZero() {
        // 12 straight training weeks, then the phone sits for 3 weeks:
        // two fully-missed weeks end the run (the current week gets the
        // Monday-morning grace, the ones before it don't).
        let counts = [Int](repeating: 2, count: 12)
        let snap = snapshot(scheduled: [], generatedAt: monday, weeklyCounts: counts)
        #expect(snap.rolledStreak(at: monday, calendar: calendar).weeks == 12)

        let oneWeekLater = calendar.date(byAdding: .day, value: 7, to: monday)!
        let rolledOne = snap.rolledStreak(at: oneWeekLater, calendar: calendar)
        // Current week empty → defers to the 11 remaining non-zero weeks.
        #expect(rolledOne.weeks == 11)
        #expect(rolledOne.counts.last == 0)

        let threeWeeksLater = calendar.date(byAdding: .day, value: 21, to: monday)!
        #expect(snap.rolledStreak(at: threeWeeksLater, calendar: calendar).weeks == 0)
    }

    @Test func sameWeekKeepsStoredValues() {
        let counts = [0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 1, 1]
        let snap = snapshot(scheduled: [], generatedAt: monday, weeklyCounts: counts)
        let sameWeek = calendar.date(byAdding: .hour, value: 30, to: monday)!
        let rolled = snap.rolledStreak(at: sameWeek, calendar: calendar)
        #expect(rolled.weeks == 4)
        #expect(rolled.counts == counts)
    }

    @Test func streakRuleMatchesTheWriter() {
        #expect(WidgetSnapshot.streak(fromWeeklyCounts: [1, 1, 1]) == 3)
        #expect(WidgetSnapshot.streak(fromWeeklyCounts: [1, 0, 1]) == 1)
        // Empty current week defers to the run before it.
        #expect(WidgetSnapshot.streak(fromWeeklyCounts: [1, 1, 0]) == 2)
        #expect(WidgetSnapshot.streak(fromWeeklyCounts: [0, 0, 0]) == 0)
    }
}
