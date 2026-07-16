import Foundation
import SwiftData
import Testing
import PlusPlusKit
@testable import PlusPlus

/// Pairing pulled GPX sidecars with their sessions (#378 PR 3). The bundle
/// path skips non-JSON by design, so this is the only door route bytes
/// enter through on a pull — and a wrong attach is worse than none.
@Suite("RouteSidecars")
struct RouteSidecarsTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routesidecars-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private let gpx = Data("<gpx></gpx>".utf8)
    private let started = Date(timeIntervalSince1970: 1_752_000_000)   // 2026-07-08 UTC

    private func finishedSession(named name: String, in context: ModelContext, startedAt: Date? = nil) -> WorkoutSession {
        let session = WorkoutSession(routineName: name, startedAt: startedAt ?? started)
        session.endedAt = (startedAt ?? started).addingTimeInterval(1800)
        context.insert(session)
        return session
    }

    private func paths(for name: String, startedAt: Date) throws -> (json: String, gpx: String, data: Data) {
        let dto = SessionDTO(routineName: name, startedAt: startedAt, endedAt: startedAt.addingTimeInterval(1800), restSeconds: 90, sets: [])
        let placement = try FileLayout.sessionPlacement(for: dto) { _ in nil }
        return (placement.path, FileLayout.routeSidecarPath(forSessionPath: placement.path), placement.data)
    }

    @Test("A restore pull pairs the sidecar through its JSON twin")
    func twinPairing() throws {
        let context = try makeContext()
        let session = finishedSession(named: "Morning Run", in: context)
        let files = try paths(for: "Morning Run", startedAt: started)

        RouteSidecars.attach(pulls: [
            FileWrite(path: files.json, data: files.data),
            FileWrite(path: files.gpx, data: gpx),
        ], context: context)

        #expect(session.routeData == gpx)
    }

    @Test("An orphan sidecar pairs by date stamp + slug, numbered suffix included")
    func orphanPairing() throws {
        let context = try makeContext()
        let session = finishedSession(named: "Morning Run", in: context)
        let stamp = FileLayout.utcDateParts(of: started).dateStamp

        RouteSidecars.attach(pulls: [
            FileWrite(path: "history/2026/\(stamp)-morning-run-2.gpx", data: gpx),
        ], context: context)

        #expect(session.routeData == gpx, "the -2 placement suffix belongs to the filename, not the routine")
    }

    @Test("Ambiguity skips: two same-day candidates get nothing")
    func ambiguousSkips() throws {
        let context = try makeContext()
        let first = finishedSession(named: "Morning Run", in: context)
        let second = finishedSession(named: "Morning Run", in: context, startedAt: started.addingTimeInterval(3600))
        let stamp = FileLayout.utcDateParts(of: started).dateStamp

        RouteSidecars.attach(pulls: [
            FileWrite(path: "history/2026/\(stamp)-morning-run.gpx", data: gpx),
        ], context: context)

        #expect(first.routeData == nil && second.routeData == nil, "a wrong route on the wrong record is worse than no map")
    }

    @Test("An existing route is never overwritten, and in-progress sessions never match")
    func attachIsConservative() throws {
        let context = try makeContext()
        let owned = finishedSession(named: "Morning Run", in: context)
        let original = Data("<gpx>original</gpx>".utf8)
        owned.routeData = original
        let inProgress = WorkoutSession(routineName: "Evening Run", startedAt: started)
        context.insert(inProgress)   // no endedAt — still running
        let stamp = FileLayout.utcDateParts(of: started).dateStamp

        RouteSidecars.attach(pulls: [
            FileWrite(path: "history/2026/\(stamp)-morning-run.gpx", data: gpx),
            FileWrite(path: "history/2026/\(stamp)-evening-run.gpx", data: gpx),
        ], context: context)

        #expect(owned.routeData == original)
        #expect(inProgress.routeData == nil, "an in-progress session's finish writes its own truth")
    }

    @Test("Non-sidecar pulls are ignored")
    func ignoresOtherPulls() throws {
        let context = try makeContext()
        _ = finishedSession(named: "Morning Run", in: context)
        RouteSidecars.attach(pulls: [
            FileWrite(path: "program/routines/morning-run.json", data: Data("x".utf8)),
            FileWrite(path: "README.gpx", data: gpx),   // not under history/
        ], context: context)
        // Nothing to assert beyond "didn't crash / didn't attach":
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.allSatisfy { $0.routeData == nil })
    }
}
