import Foundation
import Testing
@testable import PlusPlusKit

@Suite("Operator ChangeSpec")
struct OperatorChangeTests {
    // MARK: - Normalization

    @Test("Targets are trimmed and blanks dropped")
    func targetsNormalize() {
        let spec = ChangeSpec(operation: .update, entity: .routine, targets: ["  Push Day ", "", "  "], values: ChangeValues(name: "Push"))
        #expect(spec.normalized.targets == ["Push Day"])
    }

    @Test("create superset reads as the update that forms one")
    func createSupersetNormalizesToUpdate() {
        let spec = ChangeSpec(
            operation: .create, entity: .superset,
            targets: ["Bench Press", "Barbell Row"],
            filter: ChangeFilter(inRoutine: "Push Day")
        )
        #expect(spec.normalized.operation == .update)
    }

    @Test("A create whose name landed in targets adopts it as values.name")
    func createNameFromTargets() {
        let spec = ChangeSpec(operation: .create, entity: .routine, targets: ["Leg Day"])
        let normalized = spec.normalized
        #expect(normalized.values?.name == "Leg Day")
        #expect(normalized.targets.isEmpty)
    }

    // MARK: - Validation matrix

    @Test("A well-formed bulk transform validates clean")
    func stretchBulkValidates() {
        let spec = ChangeSpec(
            operation: .update, entity: .exercise,
            filter: ChangeFilter(nameContains: "stretch", trackedBy: .reps),
            values: ChangeValues(trackBy: .duration, durationSeconds: 30)
        )
        #expect(spec.validationIssues().isEmpty)
    }

    @Test("create needs a name")
    func createNeedsName() {
        let spec = ChangeSpec(operation: .create, entity: .routine)
        #expect(spec.validationIssues().contains("create needs values.name"))
    }

    @Test("create takes no filter")
    func createRejectsFilter() {
        let spec = ChangeSpec(
            operation: .create, entity: .exercise,
            filter: ChangeFilter(nameContains: "x"),
            values: ChangeValues(name: "Probe Raise")
        )
        #expect(spec.validationIssues().contains("create takes no filter"))
    }

    @Test("update needs values and a selection")
    func updateNeedsValuesAndSelection() {
        let bare = ChangeSpec(operation: .update, entity: .routine)
        let issues = bare.validationIssues()
        #expect(issues.contains("update needs values"))
        #expect(issues.contains("update needs targets or a filter"))
    }

    @Test("An empty filter does not count as a selection")
    func emptyFilterIsNoSelection() {
        let spec = ChangeSpec(
            operation: .update, entity: .exercise,
            filter: ChangeFilter(),
            values: ChangeValues(reps: 12)
        )
        #expect(spec.validationIssues().contains("update needs targets or a filter"))
    }

    @Test("delete takes no values")
    func deleteRejectsValues() {
        let spec = ChangeSpec(
            operation: .delete, entity: .routine,
            targets: ["Push Day"],
            values: ChangeValues(name: "x")
        )
        #expect(spec.validationIssues().contains("delete takes no values"))
    }

    @Test("Superset edits need the routine and member names")
    func supersetNeedsRoutineAndMembers() {
        let spec = ChangeSpec(operation: .update, entity: .superset, values: ChangeValues(sets: 4))
        let issues = spec.validationIssues()
        #expect(issues.contains("superset changes need filter.inRoutine"))
        #expect(issues.contains("superset changes need member names in targets"))
    }

    @Test("Superset delete (dissolve) needs no member names")
    func supersetDeleteNeedsNoMembers() {
        let spec = ChangeSpec(
            operation: .delete, entity: .superset,
            filter: ChangeFilter(inRoutine: "Push Day")
        )
        #expect(spec.validationIssues().isEmpty)
    }

    @Test("Forming a superset needs no values; naming the members IS the change")
    func supersetFormationNeedsNoValues() {
        let formation = ChangeSpec(
            operation: .update, entity: .superset,
            targets: ["Bench Press", "Barbell Row"],
            filter: ChangeFilter(inRoutine: "Push Day")
        )
        #expect(formation.validationIssues().isEmpty)

        // A single member with no values is still an empty ask.
        let single = ChangeSpec(
            operation: .update, entity: .superset,
            targets: ["Bench Press"],
            filter: ChangeFilter(inRoutine: "Push Day")
        )
        #expect(single.validationIssues().contains("update needs values"))
    }

    @Test("Wrong-entity fields are flagged, not dropped")
    func fieldApplicability() {
        let scheduleOnExercise = ChangeSpec(
            operation: .update, entity: .exercise,
            targets: ["Plank"],
            values: ChangeValues(scheduleDays: [2])
        )
        #expect(scheduleOnExercise.validationIssues().contains("scheduleDays applies to routines only"))

        let trackByOnRoutine = ChangeSpec(
            operation: .update, entity: .routine,
            targets: ["Push Day"],
            values: ChangeValues(trackBy: .duration)
        )
        #expect(trackByOnRoutine.validationIssues().contains("trackBy applies to exercises only"))

        let setsOnExercise = ChangeSpec(
            operation: .update, entity: .exercise,
            targets: ["Plank"],
            values: ChangeValues(sets: 4)
        )
        #expect(setsOnExercise.validationIssues().contains("sets applies to supersets only"))

        let equipmentOnRoutine = ChangeSpec(
            operation: .update, entity: .routine,
            targets: ["Push Day"],
            values: ChangeValues(equipment: ["Barbell"])
        )
        #expect(equipmentOnRoutine.validationIssues().contains("equipment applies to exercises and libraries only"))

        let deltaOnExercise = ChangeSpec(
            operation: .update, entity: .exercise,
            targets: ["Plank"],
            values: ChangeValues(addEquipment: ["Jump Rope"])
        )
        #expect(deltaOnExercise.validationIssues().contains("addEquipment/removeEquipment apply to libraries only"))

        // Replace and delta in one spec is a contradiction, not a merge.
        let replaceAndDelta = ChangeSpec(
            operation: .update, entity: .library,
            targets: ["Home"],
            values: ChangeValues(equipment: ["Barbell"], addEquipment: ["Jump Rope"])
        )
        #expect(replaceAndDelta.validationIssues().contains("use equipment (replaces the list) or addEquipment/removeEquipment, not both"))

        // The legitimate delta spelling stays clean.
        let addToLibrary = ChangeSpec(
            operation: .update, entity: .library,
            targets: ["Home"],
            values: ChangeValues(addEquipment: ["Jump Rope"])
        )
        #expect(addToLibrary.validationIssues().isEmpty)
    }

    @Test("A library update naming no target is valid; other entities and deletes still name theirs")
    func libraryUpdateDefaultsToActive() {
        // "Remove the barbell from my equipment" never names a library —
        // the engine resolves it to the ACTIVE one downstream.
        let unnamed = ChangeSpec(
            operation: .update, entity: .library,
            values: ChangeValues(removeEquipment: ["Barbell"])
        )
        #expect(unnamed.validationIssues().isEmpty)

        let exerciseStillNeedsTargets = ChangeSpec(
            operation: .update, entity: .exercise,
            values: ChangeValues(reps: 10)
        )
        #expect(exerciseStillNeedsTargets.validationIssues().contains("update needs targets or a filter"))

        // A delete must always say what it deletes.
        let unnamedDelete = ChangeSpec(operation: .delete, entity: .library)
        #expect(unnamedDelete.validationIssues().contains("delete needs targets or a filter"))
    }

    @Test("Inapplicable filter criteria are rejected, never silently widened")
    func filterApplicability() {
        // An ignored criterion would select EVERYTHING the entity has —
        // the exact opposite of the stated selection.
        let inRoutineOnExercise = ChangeSpec(
            operation: .update, entity: .exercise,
            filter: ChangeFilter(inRoutine: "Push Day"),
            values: ChangeValues(trackBy: .duration)
        )
        #expect(inRoutineOnExercise.validationIssues().contains("filter.inRoutine applies to superset changes only"))

        let muscleOnRoutine = ChangeSpec(
            operation: .update, entity: .routine,
            filter: ChangeFilter(muscleGroup: .quads),
            values: ChangeValues(restSeconds: 60)
        )
        #expect(muscleOnRoutine.validationIssues().contains("filter.muscleGroup applies to exercises only"))

        let trackedByOnLibrary = ChangeSpec(
            operation: .delete, entity: .library,
            filter: ChangeFilter(trackedBy: .reps)
        )
        #expect(trackedByOnLibrary.validationIssues().contains("filter.trackedBy applies to exercises only"))

        // The legitimate uses stay clean.
        let stretchBulk = ChangeSpec(
            operation: .update, entity: .exercise,
            filter: ChangeFilter(nameContains: "stretch", trackedBy: .reps),
            values: ChangeValues(trackBy: .duration)
        )
        #expect(stretchBulk.validationIssues().isEmpty)
    }

    // MARK: - TrackMode

    @Test("TrackMode matching is disjoint over the common shapes")
    func trackModeMatching() {
        #expect(TrackMode.reps.matches(.repsOnly))
        #expect(!TrackMode.reps.matches(.weightReps))
        #expect(!TrackMode.reps.matches(.durationOnly))

        #expect(TrackMode.weightReps.matches(.weightReps))
        #expect(!TrackMode.weightReps.matches(.repsOnly))

        #expect(TrackMode.duration.matches(.durationOnly))
        #expect(!TrackMode.duration.matches(.repsOnly))
        // A richer time-driven cardio profile still reads as duration.
        #expect(TrackMode.duration.matches(MetricProfile([.duration, .distance, .pace])))
        // But rep-tracked loaded work never reads as duration.
        #expect(!TrackMode.duration.matches(MetricProfile([.weight, .reps, .duration])))
    }

    @Test("TrackMode round-trips through its target profile")
    func trackModeProfiles() {
        for mode in TrackMode.allCases {
            #expect(mode.matches(mode.profile), "\(mode) should match its own profile")
        }
    }

    // MARK: - Weekdays

    @Test("Weekday names parse to Calendar numbers, unknowns to nil")
    func weekdayParsing() {
        #expect(ChangeSpec.weekdayNumber(from: "mon") == 2)
        #expect(ChangeSpec.weekdayNumber(from: "Monday") == 2)
        #expect(ChangeSpec.weekdayNumber(from: " SUN ") == 1)
        #expect(ChangeSpec.weekdayNumber(from: "thurs") == 5)
        #expect(ChangeSpec.weekdayNumber(from: "sat") == 7)
        #expect(ChangeSpec.weekdayNumber(from: "someday") == nil)
    }

    @Test("Spoken names read aloud cleanly")
    func spokenNames() {
        #expect(TrackMode.reps.spokenName == "reps")
        #expect(TrackMode.duration.spokenName == "duration")
        #expect(TrackMode.weightReps.spokenName == "weight and reps")
    }
}
