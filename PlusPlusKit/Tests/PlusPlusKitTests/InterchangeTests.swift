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
                    videoURL: "https://youtu.be/ykZHbcGNfII",
                    defaultReps: 15,
                    defaultRepsUpper: 20
                ),
                ExerciseDTO(name: "Y Raise", muscleGroup: .shoulders, exerciseType: .weightReps, equipment: ["Dumbbells", "Bench"]),
                ExerciseDTO(name: "T Raise", muscleGroup: .shoulders, exerciseType: .weightReps, equipment: ["Bench", "Dumbbells"]),
            ],
            routines: [
                RoutineDTO(name: "Shoulder PT", restSeconds: 60, notes: "Every day during rehab.", groups: [
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
                    routineName: "Shoulder PT",
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
            routines: forward.routines,
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
        let json = #"{"schemaVersion": 99, "exercises": [], "routines": [], "sessions": []}"#
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
            routines: [
                RoutineDTO(name: "Arms", restSeconds: 5, groups: [
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

    @Test("Validator bounds exercise default targets (#187)")
    func validatorChecksDefaultTargets() {
        let bundle = ExportBundle(
            exercises: [
                ExerciseDTO(name: "Curl", muscleGroup: .biceps, exerciseType: .weightReps, equipment: [],
                            defaultWeight: -5, defaultReps: 0),
                ExerciseDTO(name: "Row", muscleGroup: .back, exerciseType: .weightReps, equipment: [],
                            defaultRepsUpper: 12),
                ExerciseDTO(name: "Plank", muscleGroup: .core, exerciseType: .duration, equipment: [],
                            defaultDurationSeconds: 0),
                ExerciseDTO(name: "Press", muscleGroup: .shoulders, exerciseType: .weightReps, equipment: [],
                            defaultReps: 12, defaultRepsUpper: 10),
            ],
            routines: [],
            sessions: []
        )
        let messages = InterchangeValidator.validate(bundle).map(\.message).joined(separator: "; ")
        #expect(messages.contains("defaultReps 0 outside 1...100"))
        #expect(messages.contains("negative defaultWeight"))
        #expect(messages.contains("defaultRepsUpper without defaultReps"))
        #expect(messages.contains("non-positive defaultDurationSeconds"))
        #expect(messages.contains("defaultRepsUpper 10 must exceed defaultReps 12"))
    }

    @Test("Slugs: lowercase, dashes, apostrophes folded")
    func slugs() {
        #expect(Slug.make("Band Pulses") == "band-pulses")
        #expect(Slug.make("Y's and T's") == "ys-and-ts")
        #expect(Slug.make("Shoulder PT") == "shoulder-pt")
        #expect(Slug.make("  Odd   Spacing!  ") == "odd-spacing")
        #expect(Slug.make("1/2 Kneeling Trunk Rotation") == "1-2-kneeling-trunk-rotation")
    }

    // MARK: - Equipment libraries (additive to schema v1)

    @Test("Equipment libraries round-trip, sorted by name and gear")
    func equipmentLibrariesRoundTrip() throws {
        let bundle = ExportBundle(
            exercises: [], routines: [], sessions: [],
            equipmentLibraries: [
                EquipmentLibraryDTO(name: "Hotel", equipment: []),
                EquipmentLibraryDTO(name: "Home", equipment: ["Rowing Machine", "Dumbbells"]),
            ]
        )
        #expect(bundle.equipmentLibraries?.map(\.name) == ["Home", "Hotel"])
        #expect(bundle.equipmentLibraries?.first?.equipment == ["Dumbbells", "Rowing Machine"])
        let decoded = try InterchangeCodec.decode(ExportBundle.self, from: InterchangeCodec.encode(bundle))
        #expect(decoded == bundle)
    }

    @Test("Pre-libraries files stay valid, and absent stays absent on re-encode")
    func equipmentLibrariesAreAdditive() throws {
        let legacy = #"{"schemaVersion": 1, "exercises": [], "routines": [], "sessions": []}"#
        let decoded = try InterchangeCodec.decode(ExportBundle.self, from: Data(legacy.utf8))
        #expect(decoded.equipmentLibraries == nil)
        let reEncoded = String(decoding: try InterchangeCodec.encode(decoded), as: UTF8.self)
        #expect(!reEncoded.contains("equipmentLibraries"), "absent must not materialize — pre-libraries bundles stay byte-identical")
    }

    @Test("Validator flags duplicate and empty library names, empty gear entries")
    func equipmentLibraryValidation() {
        let bundle = ExportBundle(
            exercises: [], routines: [], sessions: [],
            equipmentLibraries: [
                EquipmentLibraryDTO(name: "Home", equipment: ["Barbell", " "]),
                EquipmentLibraryDTO(name: "home", equipment: []),
                EquipmentLibraryDTO(name: "  ", equipment: []),
            ]
        )
        let messages = InterchangeValidator.validate(bundle).map(\.message).joined(separator: "; ")
        #expect(messages.contains("duplicate library name"))
        #expect(messages.contains("library name is empty"))
        #expect(messages.contains("equipment entry is empty"))
    }

    @Test("Repo layout: libraries get program/equipment-libraries/<slug>.json files")
    func equipmentLibraryFileLayout() throws {
        #expect(FileLayout.equipmentLibraryPath(for: "Hotel Gym") == "program/equipment-libraries/hotel-gym.json")
        let bundle = ExportBundle(
            exercises: [], routines: [], sessions: [],
            equipmentLibraries: [EquipmentLibraryDTO(name: "Home", equipment: ["Dumbbells"])]
        )
        let files = try FileLayout.templateFiles(for: bundle)
        let libraryFile = try #require(files.first { $0.path == "program/equipment-libraries/home.json" })
        let document = try InterchangeCodec.decode(EquipmentLibraryDocument.self, from: libraryFile.data)
        #expect(document.library.name == "Home")
        #expect(document.library.equipment == ["Dumbbells"])
    }

    // MARK: - Equipment records (additive to schema v1)

    @Test("Equipment records round-trip; absent stays absent on re-encode")
    func equipmentRecordsRoundTrip() throws {
        let bundle = ExportBundle(
            exercises: [], routines: [], sessions: [],
            equipment: [
                EquipmentDTO(name: "Rowing Machine", isBuiltIn: true, metrics: ["pace", "distance"], distanceUnit: .meters),
                EquipmentDTO(name: "Dumbbells", isBuiltIn: true, weightStep: 2.5),
            ]
        )
        #expect(bundle.equipment?.map(\.name) == ["Dumbbells", "Rowing Machine"])
        #expect(bundle.equipment?.last?.metrics == ["distance", "pace"])
        let decoded = try InterchangeCodec.decode(ExportBundle.self, from: InterchangeCodec.encode(bundle))
        #expect(decoded == bundle)

        let legacy = #"{"schemaVersion": 1, "exercises": [], "routines": [], "sessions": []}"#
        let legacyDecoded = try InterchangeCodec.decode(ExportBundle.self, from: Data(legacy.utf8))
        #expect(legacyDecoded.equipment == nil)
        let reEncoded = String(decoding: try InterchangeCodec.encode(legacyDecoded), as: UTF8.self)
        #expect(!reEncoded.contains("\"equipment\""), "absent must not materialize")
    }

    @Test("Validator bounds equipment records: dup names, bad steps, unknown metrics")
    func equipmentRecordValidation() {
        let bundle = ExportBundle(
            exercises: [], routines: [], sessions: [],
            equipment: [
                EquipmentDTO(name: "Dumbbells", weightStep: 0),
                EquipmentDTO(name: "dumbbells"),
                EquipmentDTO(name: "Erg", metrics: ["resistence", "rest"]),
            ]
        )
        let messages = InterchangeValidator.validate(bundle).map(\.message).joined(separator: "; ")
        #expect(messages.contains("duplicate equipment name"))
        #expect(messages.contains("weightStep 0.0 must be finite and positive"))
        #expect(messages.contains("metrics.resistence is not a known metric"))
        #expect(messages.contains("metrics may not include rest"))
    }

    @Test("Repo layout: gear records get program/equipment/<slug>.json files")
    func equipmentRecordFileLayout() throws {
        let bundle = ExportBundle(
            exercises: [], routines: [], sessions: [],
            equipment: [EquipmentDTO(name: "Dumbbells", isBuiltIn: true, weightStep: 2.5)]
        )
        let files = try FileLayout.templateFiles(for: bundle)
        let file = try #require(files.first { $0.path == "program/equipment/dumbbells.json" })
        let document = try InterchangeCodec.decode(EquipmentDocument.self, from: file.data)
        #expect(document.equipment.weightStep == 2.5)
    }
}
