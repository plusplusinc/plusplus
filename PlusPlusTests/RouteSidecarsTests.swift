import Foundation
import SwiftData
import Testing
import PlusPlusKit
@testable import PlusPlus

/// Pairing pulled GPX sidecars with their sessions (#378 PR 3). The bundle
/// path skips non-JSON by design, so this is the only door route bytes
/// enter through on a pull. Pairing is deterministic (the filename's
/// `-N` ordinal names the Nth same-day session in start order — the same
/// rule that minted the name), pulled bytes win, and anything unplaceable
/// is returned for banking rather than dropped.
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
    private let started = Date(timeIntervalSince1970: 1_752_000_000)

    private func finishedSession(named name: String, in context: ModelContext, startedAt: Date? = nil) -> WorkoutSession {
        let session = WorkoutSession(routineName: name, startedAt: startedAt ?? started)
        session.endedAt = (startedAt ?? started).addingTimeInterval(1800)
        context.insert(session)
        return session
    }

    private var stamp: String { FileLayout.utcDateParts(of: started).dateStamp }

    @Test("A restore pull pairs the sidecar through its JSON twin")
    func twinPairing() throws {
        let context = try makeContext()
        let session = finishedSession(named: "Morning Run", in: context)
        let dto = SessionDTO(routineName: "Morning Run", startedAt: started, endedAt: started.addingTimeInterval(1800), restSeconds: 90, sets: [])
        let placement = try FileLayout.sessionPlacement(for: dto) { _ in nil }

        let unplaced = RouteSidecars.attach(pulls: [
            FileWrite(path: placement.path, data: placement.data),
            FileWrite(path: FileLayout.routeSidecarPath(forSessionPath: placement.path), data: gpx),
        ], context: context)

        #expect(session.routeData == gpx)
        #expect(unplaced.isEmpty)
    }

    @Test("The filename ordinal names the Nth same-day session in start order")
    func ordinalPairing() throws {
        let context = try makeContext()
        let first = finishedSession(named: "Morning Run", in: context)
        let second = finishedSession(named: "Morning Run", in: context, startedAt: started.addingTimeInterval(3600))
        let secondGPX = Data("<gpx>2</gpx>".utf8)

        let unplaced = RouteSidecars.attach(pulls: [
            FileWrite(path: "history/2026/\(stamp)-morning-run.gpx", data: gpx),
            FileWrite(path: "history/2026/\(stamp)-morning-run-2.gpx", data: secondGPX),
        ], context: context)

        #expect(first.routeData == gpx, "the unsuffixed name is the earliest start — placement's own rule")
        #expect(second.routeData == secondGPX)
        #expect(unplaced.isEmpty)
    }

    @Test("An ordinal with no matching session is returned for banking, not guessed")
    func unresolvedOrdinalBanks() throws {
        let context = try makeContext()
        let only = finishedSession(named: "Morning Run", in: context)

        let unplaced = RouteSidecars.attach(pulls: [
            FileWrite(path: "history/2026/\(stamp)-morning-run-2.gpx", data: gpx),
        ], context: context)

        #expect(only.routeData == nil, "a -2 sidecar names a second session; guessing the first would be wrong")
        #expect(unplaced.map(\.path) == ["history/2026/\(stamp)-morning-run-2.gpx"])
    }

    @Test("Pulled bytes win over a stale local route")
    func pulledBytesWin() throws {
        let context = try makeContext()
        let session = finishedSession(named: "Morning Run", in: context)
        session.routeData = Data("<gpx>stale</gpx>".utf8)
        let edited = Data("<gpx>hand-edited-in-repo</gpx>".utf8)

        RouteSidecars.attach(pulls: [
            FileWrite(path: "history/2026/\(stamp)-morning-run.gpx", data: edited),
        ], context: context)

        #expect(session.routeData == edited, "refusing the pull would push the stale bytes back over the user's commit")
    }

    @Test("In-progress sessions never match; non-sidecar pulls are ignored")
    func conservativeElsewhere() throws {
        let context = try makeContext()
        let inProgress = WorkoutSession(routineName: "Evening Run", startedAt: started)
        context.insert(inProgress)   // no endedAt — still running

        let unplaced = RouteSidecars.attach(pulls: [
            FileWrite(path: "history/2026/\(stamp)-evening-run.gpx", data: gpx),
            FileWrite(path: "program/routines/evening-run.json", data: Data("x".utf8)),
            FileWrite(path: "README.gpx", data: gpx),   // not under history/
        ], context: context)

        #expect(inProgress.routeData == nil, "an in-progress session's finish writes its own truth")
        #expect(unplaced.map(\.path) == ["history/2026/\(stamp)-evening-run.gpx"])
    }

    @Test("Slug interpretations try the literal name before the ordinal split")
    func interpretationOrder() {
        let plain = RouteSidecars.interpretations(of: "morning-run")
        #expect(plain.count == 1 && plain[0] == ("morning-run", 1))

        let suffixed = RouteSidecars.interpretations(of: "morning-run-2")
        #expect(suffixed.count == 2)
        #expect(suffixed[0] == ("morning-run-2", 1), "a routine genuinely named '… 2' matches first")
        #expect(suffixed[1] == ("morning-run", 2))

        // "-1" is never a placement suffix (the first placement is unsuffixed).
        let dashOne = RouteSidecars.interpretations(of: "fast-1")
        #expect(dashOne.count == 1)
    }
}

/// The push side's route lookup (#378 PR 3): `routeData` is an
/// `.externalStorage` attribute, which predicates can't reliably query —
/// the fetch filters on `endedAt` only and the route filter runs in
/// memory. This pins the whole feature's entry point against a real store
/// (a silent predicate-translation failure would no-op sidecar push).
@Suite("Route sidecar push lookup")
@MainActor
struct RouteSidecarLookupTests {
    @Test("Only finished route-carrying sessions enter the map")
    func lookup() throws {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routelookup-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
        let started = Date(timeIntervalSince1970: 1_752_000_000)

        let run = WorkoutSession(routineName: "Probe Run", startedAt: started)
        run.endedAt = started.addingTimeInterval(1800)
        run.routeData = Data("<gpx></gpx>".utf8)
        context.insert(run)
        let lift = WorkoutSession(routineName: "Probe Lift", startedAt: started)
        lift.endedAt = started.addingTimeInterval(1800)
        context.insert(lift)
        let unfinished = WorkoutSession(routineName: "Probe Live", startedAt: started)
        unfinished.routeData = Data("<gpx>live</gpx>".utf8)
        context.insert(unfinished)
        try context.save()

        let routes = GitHubSyncCoordinator.routeSidecars(context: context)

        #expect(routes.count == 1)
        #expect(routes.values.first == Data("<gpx></gpx>".utf8))
    }
}
