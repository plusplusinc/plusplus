import Foundation
import Observation
import PlusPlusKit

@Observable
final class ExerciseFilterState {
    var searchText: String = ""
    var selectedMuscleGroups: Set<MuscleGroup> = []
    var selectedEquipment: Set<Equipment> = []
    /// #113 escape hatch: exercises needing equipment you don't have are
    /// hidden by default; "show all" reveals them (the row then shows
    /// what's missing). Availability is the ACTIVE equipment library's
    /// membership — callers pass it in, since only views know it live.
    var showUnavailable = false

    /// `overridingShowUnavailable` lets a caller count what the
    /// availability filter is hiding (the §H escape hatch) without
    /// mutating state.
    func filteredExercises(
        from allExercises: [Exercise],
        available: Set<String>,
        overridingShowUnavailable: Bool? = nil
    ) -> [Exercise] {
        allExercises.filter { exercise in
            matchesSearch(exercise) && matchesMuscleGroup(exercise)
                && matchesEquipment(exercise)
                && ((overridingShowUnavailable ?? showUnavailable)
                    || Self.missingEquipment(for: exercise, available: available).isEmpty)
        }
        .sorted { $0.name < $1.name }
    }

    /// Equipment the exercise needs but the active library doesn't have —
    /// drives both the hide and the "needs squat rack" cue when shown
    /// anyway.
    static func missingEquipment(for exercise: Exercise, available: Set<String>) -> [String] {
        // isDeleted: a just-deleted custom equipment lingers in the
        // relationship until save and must not count as available or
        // missing (bug hunt B1).
        exercise.equipment.filter { !$0.isDeleted && !available.contains($0.name) }.map(\.name).sorted()
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
