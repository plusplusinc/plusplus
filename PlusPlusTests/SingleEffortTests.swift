import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// One effort is not a repetition of anything (Dave, build 158: "if I go for
/// a run, usually I'm just gonna run, and then stop, not log rep").
@Suite("Single effort")
struct SingleEffortTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("soleeffort-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A bare log reads as strength; pass `cardio: true` for the
    /// continuous-effort shape the suite is about.
    @discardableResult
    private func addLog(_ session: WorkoutSession, _ context: ModelContext, order: Int, name: String, cardio: Bool = false) -> SetLog {
        let log = SetLog(order: order, groupIndex: order, setNumber: 1, exerciseName: name)
        context.insert(log)
        if cardio { log.metricProfile = MetricProfile([.distance, .duration, .pace]) }
        log.session = session
        return log
    }

    @Test("A quick-started run is one effort")
    func lonelyRun() throws {
        let context = ModelContext(try makeContainer())
        let session = WorkoutSession.startEmpty(context: context)
        addLog(session, context, order: 0, name: "Probe Run", cardio: true)
        #expect(session.isSingleEffort)
    }

    @Test("One strength set is a count of one, not a single effort")
    func oneSetIsNotAnEffort() throws {
        let context = ModelContext(try makeContainer())
        let session = WorkoutSession.startEmpty(context: context)
        addLog(session, context, order: 0, name: "Probe Press")
        // Ad-hoc sessions never auto-finish (design-review 9): one bench
        // set is a session you probably ADD to, so the key keeps logging
        // and the staged Add-or-Finish ask keeps its job.
        #expect(!session.isSingleEffort)
    }

    @Test("A second effort ends it, whether it is rounds or another exercise")
    func moreThanOne() throws {
        let context = ModelContext(try makeContainer())

        let intervals = WorkoutSession.startEmpty(context: context)
        addLog(intervals, context, order: 0, name: "Probe Row")
        addLog(intervals, context, order: 1, name: "Probe Row")
        #expect(!intervals.isSingleEffort, "4 x 500 m is exactly the case that DOES count")

        let mixed = WorkoutSession.startEmpty(context: context)
        addLog(mixed, context, order: 0, name: "Probe Run")
        addLog(mixed, context, order: 1, name: "Probe Press")
        #expect(!mixed.isSingleEffort, "a run then core work is not over when the run is")
    }

    @Test("Adding an exercise mid-effort takes the ending back")
    func addingDuringTheEffort() throws {
        let context = ModelContext(try makeContainer())
        let session = WorkoutSession.startEmpty(context: context)
        addLog(session, context, order: 0, name: "Probe Run", cardio: true)
        #expect(session.isSingleEffort)

        // Reachable from the overview sheet while the effort runs, which is
        // why the finish can be merged into the key without stranding the
        // build-as-you-go path.
        addLog(session, context, order: 1, name: "Probe Press")
        #expect(!session.isSingleEffort, "live, not stored — the key goes back to logging")
    }
}
