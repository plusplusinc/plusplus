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
        let matched = allExercises.filter { exercise in
            matchesMuscleGroup(exercise) && matchesEquipment(exercise)
                && ((overridingShowUnavailable ?? showUnavailable)
                    || Self.missingEquipment(for: exercise, available: available).isEmpty)
        }
        .sorted { $0.name < $1.name }
        // Forgiving search (the FuzzySearch tiers), ranked best-first —
        // ties keep the alphabetical order from above. A blank search
        // passes everything through unchanged.
        return FuzzySearch.ranked(matched, query: searchText, key: Self.searchHaystack)
    }

    /// Name plus muscle group, so "hamstring curl" finds Leg Curl even
    /// though no exercise carries the word "hamstring" in its name.
    static func searchHaystack(_ exercise: Exercise) -> String {
        "\(exercise.name) \(exercise.muscleGroup.displayName)"
    }

    // MARK: - Create-from-here prefill

    /// What a create action launched from this narrowed list should
    /// start from: whatever was being searched for is almost certainly
    /// the thing being created.
    var prefillName: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    /// A muscle group carries over only when exactly one is filtered —
    /// an exercise has exactly one, so a multi-select is ambiguous and
    /// the editor keeps its own default.
    var prefillMuscleGroup: MuscleGroup? {
        selectedMuscleGroups.count == 1 ? selectedMuscleGroups.first : nil
    }

    /// Filtered gear carries over whole (visible, chip-removable state
    /// in the editor) — minus just-deleted stragglers: this filter
    /// state outlives picker presentations, and a deleted model
    /// lingering in it (bug hunt B1) must never be WRITTEN into a new
    /// exercise's relationships.
    var prefillEquipment: Set<Equipment> {
        selectedEquipment.filter { !$0.isDeleted }
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
