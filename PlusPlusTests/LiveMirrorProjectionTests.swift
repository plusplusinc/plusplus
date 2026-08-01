import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// Stage 1 of the watch repair (#510): the projection rules that keep a
/// late or duplicate wrist op from corrupting the durable record, and
/// the live-elsewhere registry salvage consults.
@Suite("Live mirror projection")
struct LiveMirrorProjectionTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("livemirror-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func op(_ sessionId: UUID, seq: Int, _ kind: LiveSession.Kind) -> LiveSession.Op {
        LiveSession.Op(opId: UUID(), sessionId: sessionId, origin: .watch, seq: seq, at: Date(), kind: kind)
    }

    @Test("A late logSet fills a hole on a finished session but never rewrites a committed set")
    func finishedGuardFillsHolesOnly() throws {
        let context = ModelContext(try makeContainer())
        let session = WorkoutSession(routineName: "Probe Run", startedAt: Date(), restSeconds: 60)
        session.sessionId = UUID()
        context.insert(session)
        let done = SetLog(order: 0, groupIndex: 0, setNumber: 1, exerciseName: "Probe Row")
        context.insert(done)
        done.actualReps = 8
        done.completedAt = Date()
        done.session = session
        let hole = SetLog(order: 1, groupIndex: 1, setNumber: 1, exerciseName: "Probe Row")
        context.insert(hole)
        hole.session = session
        session.finish()
        try context.save()
        defer { LiveMirror.clearRemoteActivity(session.sessionId) }

        // The hole fills: a set the ops lost, that no result will repair.
        LiveMirror.project(op(session.sessionId, seq: 1, .logSet(
            index: 1, actualWeight: nil, actualReps: 5, actualDuration: nil,
            extras: [:], completedAt: Date()
        )), into: context)
        #expect(hole.actualReps == 5)
        #expect(hole.completedAt != nil)

        // The committed set refuses a rewrite.
        LiveMirror.project(op(session.sessionId, seq: 2, .logSet(
            index: 0, actualWeight: nil, actualReps: 99, actualDuration: nil,
            extras: [:], completedAt: Date()
        )), into: context)
        #expect(done.actualReps == 8)
    }

    @Test("Profile widening keeps isOutdoor and paceReference")
    func wideningKeepsFlags() throws {
        let context = ModelContext(try makeContainer())
        let session = WorkoutSession(routineName: "Probe Run", startedAt: Date(), restSeconds: 60)
        session.sessionId = UUID()
        context.insert(session)
        let log = SetLog(order: 0, groupIndex: 0, setNumber: 1, exerciseName: "Probe Run")
        context.insert(log)
        log.metricProfile = MetricProfile([.distance], distanceUnit: .miles,
                                          isOutdoor: true, paceReference: .per100Yards)
        log.session = session
        try context.save()
        defer { LiveMirror.clearRemoteActivity(session.sessionId) }

        // A measured pace on a distance-only profile widens the snapshot —
        // and must not strip the flags that file the workout in Health.
        let extras = MetricValues.toRaw([.pace: 540]) ?? [:]
        LiveMirror.project(op(session.sessionId, seq: 1, .logSet(
            index: 0, actualWeight: nil, actualReps: nil, actualDuration: nil,
            extras: extras, completedAt: Date()
        )), into: context)
        let profile = log.metricProfile
        #expect(profile.contains(.pace))
        #expect(profile.isOutdoor)
        #expect(profile.paceReference == .per100Yards)
    }

    @Test("A started op resolves its routine by uuid, not name")
    func materializeResolvesByUuid() throws {
        let context = ModelContext(try makeContainer())
        let routine = Routine(name: "Probe Push", transitionSeconds: 77)
        context.insert(routine)
        try context.save()

        // The wrist knew this routine by an old name; the uuid is the
        // identity that survives the rename (#511).
        let sid = UUID()
        defer { LiveMirror.clearRemoteActivity(sid) }
        LiveMirror.project(op(sid, seq: 0, .started(
            routineName: "Renamed Since", startedAt: Date(), restSeconds: 60,
            steps: [], routineUuid: routine.uuid
        )), into: context)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let materialized = try #require(sessions.first { $0.sessionId == sid })
        #expect(materialized.transitionSeconds == 77)
    }

    @Test("The live-elsewhere registry answers within its window and clears")
    func registryRoundTrip() {
        let id = UUID()
        #expect(!LiveMirror.isLiveElsewhere(id))
        LiveMirror.noteRemoteActivity(id)
        #expect(LiveMirror.isLiveElsewhere(id))
        LiveMirror.clearRemoteActivity(id)
        #expect(!LiveMirror.isLiveElsewhere(id))
    }

    @Test("Participation keys on logged sets; a glance's rest ops mark only liveness")
    func participationKeysOnLogs() throws {
        let context = ModelContext(try makeContainer())
        let id = UUID()
        defer { LiveMirror.clearRemoteActivity(id) }
        // A wrist that adopted a session to glance mid-rest emits
        // `.restEnded` when the countdown expires: LIVE, but it has not
        // trained — the phone must keep its Health writer (#519).
        LiveMirror.project(op(id, seq: 1, .restEnded), into: context)
        #expect(LiveMirror.isLiveElsewhere(id))
        #expect(!LiveMirror.watchParticipated(id))
        // A logged set is participation, even parked ahead of its
        // `.started` — the mark precedes the fetch.
        LiveMirror.project(op(id, seq: 2, .logSet(
            index: 0, actualWeight: nil, actualReps: 5, actualDuration: nil,
            extras: [:], completedAt: Date()
        )), into: context)
        #expect(LiveMirror.watchParticipated(id))
        // Lifecycle closure ends both registries.
        LiveMirror.clearRemoteActivity(id)
        #expect(!LiveMirror.watchParticipated(id))
        #expect(!LiveMirror.isLiveElsewhere(id))
    }
}
