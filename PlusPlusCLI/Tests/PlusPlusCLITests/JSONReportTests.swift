import Foundation
import Testing
import PlusPlusKit
@testable import plusplus

@Suite("JSON reports")
struct JSONReportTests {
    private func encodeToString<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try InterchangeCodec.encode(value), as: UTF8.self)
    }

    @Test("Lint report carries validity, counts, and structured issues")
    func lintReport() throws {
        let bad = ExportBundle(
            exercises: [],
            routines: [RoutineDTO(name: "Bad", restSeconds: 5, groups: [])],
            sessions: []
        )
        let issues = InterchangeValidator.validate(bad)
        let report = LintReport(bundle: bad, issues: issues)

        #expect(!report.valid)
        #expect(report.counts == .init(exercises: 0, routines: 1, sessions: 0))
        #expect(!report.issues.isEmpty)
        #expect(report.issues.allSatisfy { !$0.path.isEmpty && !$0.message.isEmpty })

        // Round-trips through the deterministic codec.
        let text = try encodeToString(report)
        let decoded = try InterchangeCodec.decoder().decode(LintReport.self, from: Data(text.utf8))
        #expect(decoded == report)
    }

    @Test("A clean bundle lints valid with no issues")
    func lintReportValid() throws {
        let clean = ExportBundle(
            exercises: [ExerciseDTO(name: "Push-Up", muscleGroup: .chest, exerciseType: .weightReps, equipment: [])],
            routines: [],
            sessions: []
        )
        let report = LintReport(bundle: clean, issues: InterchangeValidator.validate(clean))
        #expect(report.valid)
        #expect(report.issues.isEmpty)
        let text = try encodeToString(report)
        #expect(text.contains("\"valid\" : true"))
    }

    @Test("Stats report mirrors the aggregates with ISO-8601 dates")
    func statsReport() throws {
        let start = Date(timeIntervalSince1970: 3 * 86_400)
        let session = SessionDTO(
            routineName: "Push", startedAt: start,
            endedAt: start.addingTimeInterval(1800), restSeconds: 90,
            sets: [
                .init(order: 0, groupIndex: 0, setNumber: 1,
                      exerciseName: "Bench Press", exerciseType: .weightReps,
                      actualWeight: 145, actualReps: 8,
                      completedAt: start.addingTimeInterval(60)),
            ]
        )
        let report = StatsReport(stats: HistoryStats.compute(from: [session]))

        #expect(report.exercises.count == 1)
        let bench = try #require(report.exercises.first)
        #expect(bench.name == "Bench Press")
        #expect(bench.sessions == 1 && bench.sets == 1 && bench.reps == 8)
        #expect(bench.maxWeight == 145)
        #expect(bench.lastPerformed == start)

        let text = try encodeToString(report)
        #expect(text.contains("1970-01-04T00:00:00Z"))
    }

    @Test("Encoding is deterministic: same report, same bytes")
    func deterministicEncoding() throws {
        let bundle = ExportBundle(exercises: [], routines: [], sessions: [])
        let report = LintReport(bundle: bundle, issues: [])
        let first = try InterchangeCodec.encode(report)
        let second = try InterchangeCodec.encode(report)
        #expect(first == second)
    }
}
