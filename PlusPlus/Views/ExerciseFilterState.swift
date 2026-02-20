import Foundation
import Observation

@Observable
final class ExerciseFilterState {
    var searchText: String = ""
    var selectedMuscleGroups: Set<MuscleGroup> = []
    var selectedEquipment: Set<Equipment> = []

    func filteredExercises(from allExercises: [Exercise]) -> [Exercise] {
        allExercises.filter { exercise in
            matchesSearch(exercise) && matchesMuscleGroup(exercise) && matchesEquipment(exercise)
        }
        .sorted { $0.name < $1.name }
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
