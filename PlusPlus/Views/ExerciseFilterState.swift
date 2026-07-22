import Foundation
import Observation
import PlusPlusKit

@Observable
final class ExerciseFilterState {
    var searchText: String = ""
    var selectedMuscleGroups: Set<MuscleGroup> = []
    /// The picker's EQUIPMENT chip: filter to exercises that USE one of
    /// these specific pieces. Distinct from `gearMode` (availability).
    var selectedEquipment: Set<Equipment> = []
    /// Show only favorited exercises (the whole-catalog curation).
    var favoritesOnly = false
    /// Gear-availability mode (nil = All). `.withKit`/`.withoutKit` test
    /// against the active kit passed to `filteredExercises`; `.handPicked`
    /// tests against `pickedGearNames`.
    var gearMode: GearMode?
    /// The hand-picked gear set for `.handPicked` mode. Names, not IDs, so
    /// the choice survives reinstalls and imports (the memberNames
    /// convention).
    var pickedGearNames: Set<String> = []

    enum GearMode: String, CaseIterable, Hashable {
        case withKit, withoutKit, handPicked
    }

    /// The whole catalog, narrowed by the active filters (2026-07-17: no
    /// availability hiding — `.withKit`/`.withoutKit`/`.handPicked` are
    /// explicit, opt-in gear modes, and All shows everything). `kitNames`
    /// is the active kit's membership, for the gear modes.
    func filteredExercises(from allExercises: [Exercise], kitNames: Set<String>) -> [Exercise] {
        let matched = allExercises.filter { exercise in
            matchesFavorites(exercise)
                && matchesMuscleGroup(exercise)
                && matchesEquipment(exercise)
                && matchesGear(exercise, kitNames: kitNames)
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

    /// Equipment the exercise needs but the given set doesn't have —
    /// drives the gear modes and the "needs squat rack" cue.
    static func missingEquipment(for exercise: Exercise, available: Set<String>) -> [String] {
        // isDeleted: a just-deleted custom equipment lingers in the
        // relationship until save and must not count as available or
        // missing (bug hunt B1).
        exercise.equipment.filter { !$0.isDeleted && !available.contains($0.name) }.map(\.name).sorted()
    }

    /// Catalog exercises that hit the SAME muscle group as `exercise` and are
    /// doable with the given kit — the substitution pool for the equipment
    /// resolve sheet's "swap the moves" step (2026-07-22). Muscle matching is
    /// the single coarse `MuscleGroup` (the only muscle signal the model
    /// carries), so it reads as "another <muscle> move your kit can do" — blunt
    /// for compounds, clean for isolation work. The exercise itself and any
    /// just-deleted straggler drop out.
    static func kitDoableAlternatives(for exercise: Exercise, in catalog: [Exercise], kit: Set<String>) -> [Exercise] {
        catalog.filter { candidate in
            candidate !== exercise
                && !candidate.isDeleted
                && candidate.muscleGroup == exercise.muscleGroup
                && missingEquipment(for: candidate, available: kit).isEmpty
        }
        .sorted { $0.name < $1.name }
    }

    private func matchesFavorites(_ exercise: Exercise) -> Bool {
        !favoritesOnly || exercise.isFavorite
    }

    private func matchesGear(_ exercise: Exercise, kitNames: Set<String>) -> Bool {
        switch gearMode {
        case nil: true
        case .withKit: Self.missingEquipment(for: exercise, available: kitNames).isEmpty
        case .withoutKit: !Self.missingEquipment(for: exercise, available: kitNames).isEmpty
        case .handPicked: Self.missingEquipment(for: exercise, available: pickedGearNames).isEmpty
        }
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

    // MARK: - Persistence (device-local, interchange-excluded)

    /// The catalog filters persist across launches (Dave: "set it and it
    /// stays"). Namespaced @AppStorage keys, the same device-local
    /// convention as the active-kit pointer. Search text is deliberately
    /// NOT persisted — a stale invisible query resurrecting reads as data
    /// loss. The owning view loads these on appear and writes back on
    /// change (ExerciseFilterState is a plain @Observable, not a View).
    enum Prefs {
        static let favoritesOnly = "exerciseCatalog.favoritesOnly"
        static let gearMode = "exerciseCatalog.gearMode"
        static let pickedGear = "exerciseCatalog.pickedGear"
        static let muscleGroups = "exerciseCatalog.muscleGroups"
    }
}
