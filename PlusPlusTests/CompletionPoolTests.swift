import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// The ONE completion pool (#505): four consumers (Today's rail, the
/// tab icon, the widget snapshot, the recap's next-up) read
/// `WorkoutSession.completions(of:in:)`, and these are the rules they
/// all inherit. The review that forced the extraction found four
/// hand-rolled variants already disagreeing.
@Suite("Completion pool")
struct CompletionPoolTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("completionpool-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func finishedSession(named name: String, in context: ModelContext, cardio: Bool = true) -> WorkoutSession {
        let session = WorkoutSession(routineName: name, startedAt: Date(), restSeconds: 60)
        context.insert(session)
        let log = SetLog(order: 0, groupIndex: 0, setNumber: 1, exerciseName: name,
                         exerciseType: cardio ? .duration : .weightReps)
        context.insert(log)
        log.actualDuration = 600
        log.completedAt = Date()
        log.session = session
        session.finish()
        return session
    }

    @Test("A quick-start-born session never completes a same-named routine")
    func quickStartExcludedFromNamePool() throws {
        let context = ModelContext(try makeContainer())
        let routine = Routine(name: "Probe Running")
        context.insert(routine)
        // The sport-named scratch run (#505, Q9-A): no routine
        // reference, marked at startQuick/materialize.
        let scratch = finishedSession(named: "Probe Running", in: context)
        scratch.isQuickStart = true
        try context.save()

        let pool = WorkoutSession.completions(of: routine, in: [scratch])
        #expect(pool.isEmpty, "a scratch run must not satisfy the routine's schedule")
    }

    @Test("A wrist import with no linked routine still completes by name")
    func wristImportCountsByName() throws {
        let context = ModelContext(try makeContainer())
        let routine = Routine(name: "Probe Steady Run")
        context.insert(routine)
        // The wrist import shape: routineName only, relationship never
        // linked, NOT a quick start — the review's Steady Run case,
        // which the first guard draft wrongly excluded.
        let wristRun = finishedSession(named: "Probe Steady Run", in: context)
        try context.save()

        let pool = WorkoutSession.completions(of: routine, in: [wristRun])
        #expect(pool.count == 1, "a scheduled routine run from the wrist must not stay due")
    }

    @Test("Identity wins, and a live reference to a different same-named routine never crosses")
    func identityWinsAndLiveReferencesNeverCross() throws {
        let context = ModelContext(try makeContainer())
        let mine = Routine(name: "Probe Push")
        context.insert(mine)
        let twin = Routine(name: "Probe Push")
        context.insert(twin)
        let mineSession = finishedSession(named: "Probe Push", in: context, cardio: false)
        mineSession.routine = mine
        let twinSession = finishedSession(named: "Probe Push", in: context, cardio: false)
        twinSession.routine = twin
        try context.save()

        // Identity: each routine sees exactly its own performance.
        let pool = WorkoutSession.completions(of: mine, in: [mineSession, twinSession])
        #expect(pool.count == 1)
        #expect(pool.first === mineSession)

        // And with NO identity matches of its own, a routine must not
        // absorb a session whose live reference points at its twin —
        // two routines sharing a name never satisfy each other's
        // schedules (the rule one of the four copies had and three
        // lacked).
        let orphanRoutine = Routine(name: "Probe Push")
        context.insert(orphanRoutine)
        try context.save()
        let orphanPool = WorkoutSession.completions(of: orphanRoutine, in: [mineSession, twinSession])
        #expect(orphanPool.isEmpty)
    }
}
