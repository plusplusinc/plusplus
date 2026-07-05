import Foundation
import Testing
import PlusPlusKit

@Suite("Interchange format")
struct InterchangeTests {
    private func makePTBundle() -> ExportBundle {
        ExportBundle(
            exercises: [
                ExerciseDTO(
                    name: "Band Pulses",
                    muscleGroup: .shoulders,
                    exerciseType: .weightReps,
                    equipment: ["Resistance Band"],
                    notes: "Elbows bent, shoulder flexed to 90°.",
                    videoURL: "https://youtu.be/ykZHbcGNfII"
                ),
                ExerciseDTO(name: "Y Raise", muscleGroup: .shoulders, exerciseType: .weightReps, equipment: ["Dumbbells", "Bench"]),
                ExerciseDTO(name: "T Raise", muscleGroup: .shoulders, exerciseType: .weightReps, equipment: ["Bench", "Dumbbells"]),
            ],
            workouts: [
                WorkoutDTO(name: "Shoulder PT", restSeconds: 60, groups: [
                    .init(sets: 3, exercises: [
                        .init(exercise: "Y Raise", weight: 5, reps: 10),
                        .init(exercise: "T Raise", weight: 5, reps: 10),
                    ]),
                    .init(sets: 3, exercises: [
                        .init(exercise: "Band Pulses", reps: 15, repsUpper: 20),
                    ]),
                ])
            ],
            sessions: [
                SessionDTO(
                    workoutName: "Shoulder PT",
                    startedAt: Date(timeIntervalSince1970: 1_751_724_660),
                    endedAt: Date(timeIntervalSince1970: 1_751_726_651),
                    restSeconds: 60,
                    sets: [
                        .init(order: 0, groupIndex: 0, setNumber: 1,
                              exerciseName: "Y Raise", exerciseType: .weightReps,
                              targetWeight: 5, targetRepsLower: 10,
                              actualWeight: 5, actualReps: 10,
                              completedAt: Date(timeIntervalSince1970: 1_751_724_800)),
                    ]
                )
            ]
        )
    }

    @Test("Round-trips through JSON losslessly")
    func roundTrip() throws {
        let bundle = makePTBundle()
        let data = try InterchangeCodec.encode(bundle)
        let decoded = try InterchangeCodec.decode(ExportBundle.self, from: data)
        #expect(decoded == bundle)
    }

    @Test("Encoding is deterministic: same bundle, same bytes")
    func deterministicEncoding() throws {
        let first = try InterchangeCodec.encode(makePTBundle())
        let second = try InterchangeCodec.encode(makePTBundle())
        #expect(first == second)
    }

    @Test("Entities are sorted regardless of construction order")
    func stableOrdering() throws {
        let forward = makePTBundle()
        let reversed = ExportBundle(
            exercises: forward.exercises.reversed(),
            workouts: forward.workouts,
            sessions: forward.sessions
        )
        #expect(try InterchangeCodec.encode(forward) == InterchangeCodec.encode(reversed))
        #expect(forward.exercises.map(\.name) == ["Band Pulses", "T Raise", "Y Raise"])
    }

    @Test("Dates encode as ISO-8601 and keys are sorted")
    func encodingShape() throws {
        let data = try InterchangeCodec.encode(makePTBundle())
        let text = String(decoding: data, as: UTF8.self)
        let expectedDate = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_751_724_660))
        #expect(text.contains(expectedDate))
        // sortedKeys puts "exercises" before "schemaVersion" before "sessions"
        let exercisesIndex = try #require(text.range(of: "\"exercises\"")).lowerBound
        let schemaIndex = try #require(text.range(of: "\"schemaVersion\"")).lowerBound
        #expect(exercisesIndex < schemaIndex)
    }

    @Test("Future schema versions are rejected loudly")
    func versionGuard() throws {
        let json = #"{"schemaVersion": 99, "exercises": [], "workouts": [], "sessions": []}"#
        #expect(throws: InterchangeCodec.CodecError.unsupportedSchemaVersion(99)) {
            try InterchangeCodec.decode(ExportBundle.self, from: Data(json.utf8))
        }
    }

    @Test("Garbage input fails as not-an-interchange-document")
    func garbageInput() {
        #expect(throws: InterchangeCodec.CodecError.notAnInterchangeDocument) {
            try InterchangeCodec.decode(ExportBundle.self, from: Data("not json".utf8))
        }
    }

    @Test("A valid bundle produces no validation issues")
    func validBundle() {
        #expect(InterchangeValidator.validate(makePTBundle()).isEmpty)
    }

    @Test("Validator reports rep-range, reference, and duplicate problems")
    func validatorCatchesProblems() {
        let bundle = ExportBundle(
            exercises: [
                ExerciseDTO(name: "Curl", muscleGroup: .biceps, exerciseType: .weightReps, equipment: []),
                ExerciseDTO(name: "curl", muscleGroup: .biceps, exerciseType: .weightReps, equipment: []),
            ],
            workouts: [
                WorkoutDTO(name: "Arms", restSeconds: 5, groups: [
                    .init(sets: 0, exercises: [
                        .init(exercise: "Ghost Exercise", reps: 20, repsUpper: 15)
                    ]),
                    .init(sets: 3, exercises: []),
                ])
            ],
            sessions: []
        )
        let issues = InterchangeValidator.validate(bundle)
        let messages = issues.map(\.message).joined(separator: "; ")
        #expect(messages.contains("duplicate exercise name"))
        #expect(messages.contains("restSeconds 5 outside 15...600"))
        #expect(messages.contains("sets 0 outside 1...20"))
        #expect(messages.contains("unresolved exercise reference"))
        #expect(messages.contains("repsUpper 15 must exceed reps 20"))
        #expect(messages.contains("group has no exercises"))
    }

    @Test("Slugs: lowercase, dashes, apostrophes folded")
    func slugs() {
        #expect(Slug.make("Band Pulses") == "band-pulses")
        #expect(Slug.make("Y's and T's") == "ys-and-ts")
        #expect(Slug.make("Shoulder PT") == "shoulder-pt")
        #expect(Slug.make("  Odd   Spacing!  ") == "odd-spacing")
        #expect(Slug.make("1/2 Kneeling Trunk Rotation") == "1-2-kneeling-trunk-rotation")
    }
}
