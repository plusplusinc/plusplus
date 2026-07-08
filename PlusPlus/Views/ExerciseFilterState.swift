import Foundation
import Observation
import PlusPlusKit

@Observable
final class ExerciseFilterState {
    var searchText: String = ""
    var selectedMuscleGroups: Set<MuscleGroup> = []
    var selectedEquipment: Set<Equipment> = []
    /// #113 escape hatch: exercises needing equipment you don't own are
    /// hidden by default; "show all" reveals them (the row then shows
    /// what's missing).
    var showUnowned = false

    /// `overridingShowUnowned` lets a caller count what the ownership
    /// filter is hiding (the §H escape hatch) without mutating state.
    func filteredExercises(from allExercises: [Exercise], overridingShowUnowned: Bool? = nil) -> [Exercise] {
        allExercises.filter { exercise in
            matchesSearch(exercise) && matchesMuscleGroup(exercise)
                && matchesEquipment(exercise)
                && ((overridingShowUnowned ?? showUnowned) || Self.missingEquipment(for: exercise).isEmpty)
        }
        .sorted { $0.name < $1.name }
    }

    /// Equipment the exercise needs but the user doesn't own — drives
    /// both the hide and the "needs squat rack" cue when shown anyway.
    static func missingEquipment(for exercise: Exercise) -> [String] {
        // isDeleted: a just-deleted custom equipment lingers in the
        // relationship until save and must not count as owned or
        // missing (bug hunt B1).
        exercise.equipment.filter { !$0.isDeleted && !$0.inLibrary }.map(\.name).sorted()
    }

    private func matchesOwnership(_ exercise: Exercise) -> Bool {
        showUnowned || Self.missingEquipment(for: exercise).isEmpty
    }

    private func matchesSearch(_ exercise: Exercise) -> Bool {
        searchText.isEmpty || exercise.name.localizedCaseInsensitiveContains(searchText)
    }

    private func matchesMuscleGroup(_ exercise: Exercise) -> Bool {
        selectedMuscleGroups.isEmpty || selectedMuscleGroups.contains(exercise.muscleGroup)
    }

    private func matchesEquipment(_ exercise: Exercise) -> Bool {
        guard !selectedEquipment.isEmpty else { return true }
        // Bodyweight exercises (empty equipment) excluded when equipment filter is active
        guard !exercise.equipment.isEmpty else { return false }
        // Exercise matches if any of its equipment is in the selected set
        return exercise.equipment.contains { selectedEquipment.contains($0) }
    }
}
