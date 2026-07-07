import Foundation
import Testing
import PlusPlusKit
@testable import plusplus

@Suite("HistoryStats")
struct HistoryStatsTests {
    private func session(named routine: String, day: Int, sets: [SessionDTO.SetDTO]) -> SessionDTO {
        let start = Date(timeIntervalSince1970: TimeInterval(day) * 86_400)
        return SessionDTO(
            routineName: routine,
            startedAt: start,
            endedAt: start.addingTimeInterval(1800),
            restSeconds: 90,
            sets: sets
        )
    }

    private func completedSet(order: Int, exercise: String, reps: Int? = nil, weight: Double? = nil, duration: Int? = nil) -> SessionDTO.SetDTO {
        .init(
            order: order, groupIndex: 0, setNumber: order + 1,
            exerciseName: exercise, exerciseType: duration == nil ? .weightReps : .duration,
            actualWeight: weight, actualReps: reps, actualDuration: duration,
            completedAt: Date(timeIntervalSince1970: 1)
        )
    }

    @Test("Aggregates sets, reps, best weight, and last-performed per exercise")
    func aggregates() {
        let sessions = [
            session(named: "Push", day: 1, sets: [
                completedSet(order: 0, exercise: "Bench Press", reps: 10, weight: 135),
                completedSet(order: 1, exercise: "Bench Press", reps: 8, weight: 145),
            ]),
            session(named: "Push", day: 3, sets: [
                completedSet(order: 0, exercise: "Bench Press", reps: 10, weight: 140),
                completedSet(order: 1, exercise: "Plank", duration: 90),
            ]),
        ]

        let stats = HistoryStats.compute(from: sessions)
        #expect(stats.map(\.name) == ["Bench Press", "Plank"])

        let bench = stats[0]
        #expect(bench.sessionCount == 2)
        #expect(bench.setCount == 3)
        #expect(bench.totalReps == 28)
        #expect(bench.maxWeight == 145)
        #expect(bench.bestDescription(weightUnit: .lb) == "145 lb")
        #expect(bench.bestDescription(weightUnit: .kg) == "145 kg", "Numbers are unit-agnostic; only the label changes")
        #expect(bench.lastPerformed == Date(timeIntervalSince1970: 3 * 86_400))

        let plank = stats[1]
        #expect(plank.bestDescription(weightUnit: .lb) == "1:30", "Durations follow the m:ss convention")
    }

    @Test("Incomplete sets don't count")
    func skipsIncomplete() {
        var pending = completedSet(order: 0, exercise: "Bench Press", reps: 10, weight: 135)
        pending.completedAt = nil
        let stats = HistoryStats.compute(from: [session(named: "Push", day: 1, sets: [pending])])
        #expect(stats.isEmpty)
    }

    @Test("Table renders header and one row per exercise")
    func table() {
        let sessions = [
            session(named: "Push", day: 1, sets: [
                completedSet(order: 0, exercise: "Bench Press", reps: 10, weight: 135),
            ])
        ]
        let text = HistoryStats.table(for: HistoryStats.compute(from: sessions))
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("Exercise"))
        #expect(lines[1].contains("Bench Press"))
        #expect(lines[1].contains("135 lb"))
        #expect(lines[1].contains("1970-01-02"))
    }
}

@Suite("RoutineRepo layout")
struct RoutineRepoTests {
    private func makeBundle() -> ExportBundle {
        ExportBundle(
            exercises: [
                ExerciseDTO(name: "Band Pulses", muscleGroup: .shoulders, exerciseType: .weightReps, equipment: ["Resistance Band"])
            ],
            routines: [
                RoutineDTO(name: "Shoulder PT", restSeconds: 60, groups: [
                    .init(sets: 3, exercises: [.init(exercise: "Band Pulses", reps: 15, repsUpper: 20)])
                ])
            ],
            sessions: [
                SessionDTO(
                    routineName: "Shoulder PT",
                    startedAt: Date(timeIntervalSince1970: 1_782_000_000),
                    endedAt: Date(timeIntervalSince1970: 1_782_002_000),
                    restSeconds: 60,
                    sets: [
                        .init(order: 0, groupIndex: 0, setNumber: 1,
                              exerciseName: "Band Pulses", exerciseType: .weightReps,
                              targetRepsLower: 15, targetRepsUpper: 20,
                              actualReps: 18, completedAt: Date(timeIntervalSince1970: 1_782_000_500)),
                    ]
                )
            ]
        )
    }

    private func makeTempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plusplus-cli-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Bundle → layout → bundle round-trips")
    func roundTrip() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = RoutineRepo(root: root)
        let bundle = makeBundle()

        let summary = try repo.write(bundle: bundle)
        #expect(summary.written.count == 3)
        #expect(summary.written.contains("program/exercises/band-pulses.json"))
        #expect(summary.written.contains("program/routines/shoulder-pt.json"))
        #expect(summary.written.contains { $0.hasPrefix("history/") && $0.hasSuffix("-shoulder-pt.json") })

        let loaded = try repo.loadBundle()
        #expect(loaded == bundle)
    }

    @Test("Re-writing the same bundle is a no-op")
    func idempotentWrite() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = RoutineRepo(root: root)

        _ = try repo.write(bundle: makeBundle())
        let second = try repo.write(bundle: makeBundle())
        #expect(second.written.isEmpty)
        #expect(second.skipped.count == 3)
    }

    @Test("A different same-day session gets a numbered suffix, not clobbered")
    func sessionCollision() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = RoutineRepo(root: root)

        _ = try repo.write(bundle: makeBundle())

        var secondSession = makeBundle().sessions[0]
        secondSession.startedAt = secondSession.startedAt.addingTimeInterval(3600) // same UTC day
        let bundle2 = ExportBundle(exercises: [], routines: [], sessions: [secondSession])
        let summary = try repo.write(bundle: bundle2)

        #expect(summary.written.count == 1)
        #expect(summary.written[0].hasSuffix("-shoulder-pt-2.json"))

        let loaded = try repo.loadBundle()
        #expect(loaded.sessions.count == 2)
    }

    @Test("Loading a directory that isn't a routine repo fails clearly")
    func notARepo() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: RoutineRepo.RepoError.self) {
            try RoutineRepo(root: root).loadBundle()
        }
    }

    @Test("BundleSource loads a single bundle file too")
    func bundleFileSource() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("export.json")
        try InterchangeCodec.encode(makeBundle()).write(to: file)

        let loaded = try BundleSource.load(path: file.path)
        #expect(loaded == makeBundle())
    }
}
