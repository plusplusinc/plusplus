import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// One noun per finished session, on every surface.
///
/// The finish screen used to resolve the session's modality live while
/// the history rows and Today's committed cards read the FIRST log's
/// unit, so a run-then-lifting session said "5 sets" on one surface and
/// "5 reps" on another. `finish()` now snapshots the resolved primary
/// modality (the sessions-snapshot law), and every record surface reads
/// `summaryWorkUnit` from it.
@Suite("Summary work unit")
struct SummaryWorkUnitTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("summaryunit-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let cardio = MetricProfile([.distance, .duration, .pace])

    @discardableResult
    private func addLog(
        _ session: WorkoutSession, _ context: ModelContext,
        order: Int, name: String, profile: MetricProfile? = nil
    ) -> SetLog {
        let log = SetLog(order: order, groupIndex: order, setNumber: 1, exerciseName: name)
        context.insert(log)
        if let profile { log.metricProfile = profile }
        log.session = session
        return log
    }

    @Test("A mixed session snapshots ONE noun at finish, and it is the resolved primary's")
    func mixedSessionSnapshotsOneNoun() throws {
        let context = ModelContext(try makeContainer())
        let session = WorkoutSession.startEmpty(context: context)
        // The run FIRST — exactly the ordering that made the first-log
        // read on the list surfaces disagree with the finish screen.
        addLog(session, context, order: 0, name: "Probe Run", profile: cardio)
        addLog(session, context, order: 1, name: "Probe Press")
        addLog(session, context, order: 2, name: "Probe Press")

        session.finish()

        // Strength plus cardio resolves to strength, so the record counts
        // sets — and counts them the SAME everywhere.
        #expect(session.summaryWorkUnit == .set)
        // The stamp is the resolved primary, not the first log's family.
        #expect(session.summaryModalityRaw == ExerciseModality.strength.rawValue)
    }

    @Test("A pure cardio session snapshots the sport's own noun")
    func cardioSessionKeepsItsNoun() throws {
        let context = ModelContext(try makeContainer())
        let session = WorkoutSession.startEmpty(context: context)
        addLog(session, context, order: 0, name: "Probe Row", profile: cardio)

        session.finish()

        // A bare cardio profile with no exercise derives the generic
        // cardio family, which counts in efforts.
        #expect(session.summaryWorkUnit == ExerciseModality.cardio.workUnit)
    }

    @Test("A record from before the field falls back to its first log")
    func legacyRecordFallsBack() throws {
        let context = ModelContext(try makeContainer())
        let session = WorkoutSession.startEmpty(context: context)
        addLog(session, context, order: 0, name: "Probe Row", profile: cardio)
        // No finish() — a migrated record has endedAt but no snapshot.
        session.endedAt = Date()

        #expect(session.summaryModalityRaw == nil)
        #expect(session.summaryWorkUnit == ExerciseModality.cardio.workUnit,
                "nil snapshot reads the first log, which is what the surfaces did before")
    }
}
