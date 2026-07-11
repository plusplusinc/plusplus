import Foundation
import Testing
import PlusPlusKit

@Suite("InterchangeFiles")
struct InterchangeFilesTests {
    @Test("Repo files round-trip back into a bundle (inverse of templateFiles)")
    func roundTripTemplates() throws {
        let exercise = ExerciseDTO(name: "Back Squat", muscleGroup: .quads, exerciseType: .weightReps, equipment: ["Barbell"])
        let routine = RoutineDTO(name: "Leg Day", restSeconds: 120, groups: [
            .init(sets: 3, exercises: [.init(exercise: "Back Squat", reps: 5)])
        ])
        let library = EquipmentLibraryDTO(name: "Home", equipment: ["Barbell"])
        let equipment = EquipmentDTO(name: "Barbell")
        let source = ExportBundle(
            exercises: [exercise], routines: [routine], sessions: [],
            equipment: [equipment], equipmentLibraries: [library]
        )

        let files = try FileLayout.templateFiles(for: source).map { FileWrite(path: $0.path, data: $0.data) }
        let rebuilt = try InterchangeFiles.bundle(from: files)

        #expect(rebuilt.exercises == [exercise])
        #expect(rebuilt.routines == [routine])
        #expect(rebuilt.equipment == [equipment])
        #expect(rebuilt.equipmentLibraries == [library])
    }

    @Test("A history file decodes into the sessions array")
    func sessionFile() throws {
        var set = SessionDTO.SetDTO(order: 0, groupIndex: 0, setNumber: 1, exerciseName: "Push-Up", exerciseType: .weightReps)
        set.actualReps = 12
        let session = SessionDTO(routineName: "Push Day", startedAt: Date(timeIntervalSince1970: 1_751_500_000), endedAt: nil, restSeconds: 90, sets: [set])
        let placement = try FileLayout.sessionPlacement(for: session) { _ in nil }

        let rebuilt = try InterchangeFiles.bundle(from: [FileWrite(path: placement.path, data: placement.data)])

        #expect(rebuilt.sessions.count == 1)
        #expect(rebuilt.sessions.first?.routineName == "Push Day")
    }

    @Test("Non-interchange paths are ignored")
    func ignoresForeignFiles() throws {
        let files = [
            FileWrite(path: "README.md", data: Data("# hi".utf8)),
            FileWrite(path: "CLAUDE.md", data: Data("rules".utf8)),
            FileWrite(path: ".github/workflows/ci.yml", data: Data("on: push".utf8)),
        ]
        let rebuilt = try InterchangeFiles.bundle(from: files)
        #expect(rebuilt.exercises.isEmpty && rebuilt.routines.isEmpty && rebuilt.sessions.isEmpty)
    }
}
