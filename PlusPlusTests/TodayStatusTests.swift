import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// The Today tab's dynamic icon state (2026-07-24): onboarding steps and
/// scheduled workouts are "today's work", and the three reads — `.toDo`,
/// `.done`, `.clear` — must match what the timeline shows.
@Suite("Today status")
struct TodayStatusTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("todaystatus-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let calendar = Calendar.current

    private func weekday(of date: Date) -> Int {
        calendar.component(.weekday, from: date)
    }

    /// A routine with one exercise so it's startable (empty routines can't
    /// stage), scheduled as given.
    private func makeRoutine(_ name: String, schedule: RoutineSchedule, context: ModelContext) -> Routine {
        let routine = Routine(name: name)
        context.insert(routine)
        let probe = Exercise(name: "Probe \(name)", muscleGroup: .chest)
        context.insert(probe)
        _ = routine.addExerciseInNewGroup(probe, context: context)
        routine.schedule = schedule
        return routine
    }

    /// A finished ad-hoc session, so the store reads as past onboarding
    /// (it references no routine, so it satisfies no schedule). Pass
    /// `endedAt` to backdate it — a session finished on a PRIOR day proves
    /// "past onboarding" without counting as a workout TODAY.
    @discardableResult
    private func finishAdHoc(context: ModelContext, endedAt: Date? = nil) -> WorkoutSession {
        let session = WorkoutSession.startEmpty(context: context)
        session.finish()
        if let endedAt { session.endedAt = endedAt }
        return session
    }

    // MARK: - Onboarding

    @Test("Fresh install with setup unfinished is to-do")
    func onboardingUnfinished() throws {
        let context = ModelContext(try makeContainer())
        let status = TodayStatus.current(
            routines: [], sessions: [], equipmentDone: false, today: Date(), calendar: calendar
        )
        #expect(status == .toDo)
        _ = context
    }

    @Test("Setup all done with the routine scheduled ahead reads as done")
    func onboardingAllDone() throws {
        let context = ModelContext(try makeContainer())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        _ = makeRoutine("Push", schedule: .weekdays([weekday(of: tomorrow)]), context: context)
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let status = TodayStatus.current(
            routines: routines, sessions: [], equipmentDone: true, today: Date(), calendar: calendar
        )
        #expect(status == .done)
    }

    @Test("Setup done but a routine is due today stays to-do")
    func onboardingDueToday() throws {
        let context = ModelContext(try makeContainer())
        _ = makeRoutine("Push", schedule: .weekdays([weekday(of: Date())]), context: context)
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let status = TodayStatus.current(
            routines: routines, sessions: [], equipmentDone: true, today: Date(), calendar: calendar
        )
        #expect(status == .toDo)
    }

    // MARK: - Post-onboarding

    @Test("A workout scheduled today and not done is to-do")
    func dueTodayUndone() throws {
        let context = ModelContext(try makeContainer())
        _ = makeRoutine("Push", schedule: .weekdays([weekday(of: Date())]), context: context)
        finishAdHoc(context: context)
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let status = TodayStatus.current(
            routines: routines, sessions: sessions, equipmentDone: true, today: Date(), calendar: calendar
        )
        #expect(status == .toDo)
    }

    @Test("Today's scheduled workout, completed today, reads as done")
    func doneToday() throws {
        let context = ModelContext(try makeContainer())
        let routine = makeRoutine("Push", schedule: .weekdays([weekday(of: Date())]), context: context)
        let session = WorkoutSession.start(from: routine, context: context)
        session.finish()
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let status = TodayStatus.current(
            routines: routines, sessions: sessions, equipmentDone: true, today: Date(), calendar: calendar
        )
        #expect(status == .done)
    }

    @Test("A rest day with nothing scheduled and no workout today is clear")
    func restDay() throws {
        let context = ModelContext(try makeContainer())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        _ = makeRoutine("Push", schedule: .weekdays([weekday(of: tomorrow)]), context: context)
        // Past onboarding via a PRIOR workout — nothing done today.
        finishAdHoc(context: context, endedAt: yesterday)
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let status = TodayStatus.current(
            routines: routines, sessions: sessions, equipmentDone: true, today: Date(), calendar: calendar
        )
        #expect(status == .clear)
    }

    @Test("An unscheduled routine with no workout today is clear")
    func unscheduledIsClear() throws {
        let context = ModelContext(try makeContainer())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        _ = makeRoutine("Whenever", schedule: .unscheduled, context: context)
        finishAdHoc(context: context, endedAt: yesterday)
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let status = TodayStatus.current(
            routines: routines, sessions: sessions, equipmentDone: true, today: Date(), calendar: calendar
        )
        #expect(status == .clear)
    }

    // MARK: - Any workout today is the day's win (2026-07-24)

    @Test("An ad-hoc workout today, with no schedule outstanding, reads as done")
    func adHocWorkoutTodayIsDone() throws {
        let context = ModelContext(try makeContainer())
        _ = makeRoutine("Whenever", schedule: .unscheduled, context: context)
        finishAdHoc(context: context)
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let status = TodayStatus.current(
            routines: routines, sessions: sessions, equipmentDone: true, today: Date(), calendar: calendar
        )
        #expect(status == .done)
    }

    @Test("An ad-hoc workout today on a rest day (scheduled tomorrow) reads as done")
    func adHocWorkoutOnRestDayIsDone() throws {
        let context = ModelContext(try makeContainer())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        _ = makeRoutine("Push", schedule: .weekdays([weekday(of: tomorrow)]), context: context)
        finishAdHoc(context: context)
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let status = TodayStatus.current(
            routines: routines, sessions: sessions, equipmentDone: true, today: Date(), calendar: calendar
        )
        #expect(status == .done)
    }

    @Test("An ad-hoc workout done while a scheduled routine is still due stays to-do")
    func adHocWorkoutWithScheduledStillDueIsToDo() throws {
        let context = ModelContext(try makeContainer())
        _ = makeRoutine("Push", schedule: .weekdays([weekday(of: Date())]), context: context)
        // A workout today, but it doesn't satisfy the still-due scheduled
        // routine — the day stays open.
        finishAdHoc(context: context)
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let status = TodayStatus.current(
            routines: routines, sessions: sessions, equipmentDone: true, today: Date(), calendar: calendar
        )
        #expect(status == .toDo)
    }

    @Test("A carried-over missed day is to-do")
    func carriedOverIsToDo() throws {
        let context = ModelContext(try makeContainer())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let routine = makeRoutine("Push", schedule: .weekdays([weekday(of: yesterday)]), context: context)
        // Anchor the schedule well before the missed day, so yesterday's
        // occurrence counts (a schedule never carries a day it predates).
        let past = calendar.date(byAdding: .day, value: -8, to: Date())!
        routine.createdAt = past
        routine.scheduleChangedAt = past
        finishAdHoc(context: context)
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let status = TodayStatus.current(
            routines: routines, sessions: sessions, equipmentDone: true, today: Date(), calendar: calendar
        )
        #expect(status == .toDo)
    }
}
