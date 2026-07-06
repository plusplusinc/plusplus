import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("ExerciseDraft")
struct ExerciseDraftTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, Workout.self, ExerciseGroup.self, WorkoutExercise.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Name is trimmed and required")
    func nameValidation() {
        let draft = ExerciseDraft()
        draft.name = "   "
        #expect(!draft.canSave(existingNames: []))

        draft.name = "  Band Pulses  "
        #expect(draft.trimmedName == "Band Pulses")
        #expect(draft.canSave(existingNames: []))
    }

    @Test("Duplicate names are rejected case-insensitively")
    func duplicateNames() {
        let draft = ExerciseDraft()
        draft.name = "band pulses"
        #expect(draft.isDuplicate(among: ["Band Pulses", "Squat"]))
        #expect(!draft.canSave(existingNames: ["Band Pulses"]))
        #expect(draft.canSave(existingNames: ["Squat"]))
    }

    @Test("Editing an exercise doesn't flag its own name as duplicate")
    func editKeepsOwnName() {
        let draft = ExerciseDraft()
        draft.name = "Band Pulses"
        #expect(!draft.isDuplicate(among: ["Band Pulses"], excluding: "Band Pulses"))
        #expect(draft.canSave(existingNames: ["Band Pulses"], editedName: "Band Pulses"))
    }

    @Test("Video URL validation and https upgrade")
    func videoURLValidation() {
        let draft = ExerciseDraft()

        draft.videoURL = ""
        #expect(draft.normalizedVideoURL == .none)

        draft.videoURL = "https://youtu.be/ykZHbcGNfII?si=abc"
        #expect(draft.normalizedVideoURL == .valid("https://youtu.be/ykZHbcGNfII?si=abc"))

        draft.videoURL = "youtu.be/ykZHbcGNfII"
        #expect(draft.normalizedVideoURL == .valid("https://youtu.be/ykZHbcGNfII"))

        draft.videoURL = "not a url"
        #expect(draft.normalizedVideoURL == .invalid)

        draft.videoURL = "ftp://example.com/video"
        #expect(draft.normalizedVideoURL == .invalid)
    }

    @Test("Invalid video URL blocks saving")
    func invalidURLBlocksSave() {
        let draft = ExerciseDraft()
        draft.name = "Trunk Rotation"
        draft.videoURL = "not a url"
        #expect(!draft.canSave(existingNames: []))
    }

    @Test("apply(to:) writes normalized values onto the model")
    func applyToModel() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let band = Equipment(name: "Resistance Band", isBuiltIn: true)
        context.insert(band)

        let draft = ExerciseDraft()
        draft.name = "  Trunk Rotation  "
        draft.muscleGroup = .core
        draft.exerciseType = .weightReps
        draft.selectedEquipment = [band]
        draft.notes = "  Emphasize right rotation.  "
        draft.videoURL = "youtu.be/ykZHbcGNfII"

        let exercise = Exercise(name: "", muscleGroup: .chest)
        context.insert(exercise)
        draft.apply(to: exercise)

        #expect(exercise.name == "Trunk Rotation")
        #expect(exercise.muscleGroup == .core)
        #expect(exercise.equipment.map(\.name) == ["Resistance Band"])
        #expect(exercise.notes == "Emphasize right rotation.")
        #expect(exercise.videoURL == "https://youtu.be/ykZHbcGNfII")
        #expect(exercise.isBuiltIn == false)
    }

    @Test("Empty notes and video become nil on the model")
    func emptyOptionalFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let draft = ExerciseDraft()
        draft.name = "Y Raise"
        draft.notes = "   "
        draft.videoURL = ""

        let exercise = Exercise(name: "", muscleGroup: .chest)
        context.insert(exercise)
        draft.apply(to: exercise)

        #expect(exercise.notes == nil)
        #expect(exercise.videoURL == nil)
    }

    @Test("Draft round-trips from an existing exercise")
    func initFromExercise() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let exercise = Exercise(
            name: "Band Pulses",
            muscleGroup: .shoulders,
            exerciseType: .weightReps,
            notes: "Elbows bent, shoulder flexed to 90°.",
            videoURL: "https://example.com/demo"
        )
        context.insert(exercise)

        let draft = ExerciseDraft(from: exercise)
        #expect(draft.name == "Band Pulses")
        #expect(draft.muscleGroup == .shoulders)
        #expect(draft.notes == "Elbows bent, shoulder flexed to 90°.")
        #expect(draft.videoURL == "https://example.com/demo")
    }

    @Test("Rename detection: real renames only, not case tweaks or new exercises")
    func renameDetection() {
        let draft = ExerciseDraft()
        draft.name = "Banded Pulses"
        #expect(draft.isRename(of: "Band Pulses"))
        #expect(!draft.isRename(of: "banded pulses"), "Case-only changes keep the same slug and history match")
        #expect(!draft.isRename(of: nil), "A new exercise cannot be a rename")

        draft.name = "   "
        #expect(!draft.isRename(of: "Band Pulses"), "Empty names are handled by canSave, not the rename warning")
    }
}
