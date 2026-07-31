import Foundation
import PlusPlusKit

/// One active facet, named for the summary popover ("Muscle · Chest").
struct ActiveFacet: Identifiable, Equatable {
    let name: String
    let value: String
    var id: String { name }
}

/// The catalog surfaces' filter state (filtering returns 2026-07-31,
/// reversing the 2026-07-25 retirement — Dave's call). A plain value
/// struct held as `@State` per `CatalogScopeView` instance: never
/// persisted (the retired `exerciseCatalog.*` keys stay dead), reset on
/// scope change, threaded into `FindOrCreateEngine.sections` as a pure
/// parameter. Every facet is SINGLE-select in v1 (a multi-select is a
/// list, not a Menu — the tray shape can come later without moving any
/// of this). Facets AND-compose; the query ranks within the filtered
/// set. Kit availability is deliberately NOT here (#113: never a
/// filter — the missing-equipment disclosure is its surface).
///
/// An item that can't answer an active facet drops out under it (the
/// equipmentCategories precedent: customs carry no category/pattern/
/// mechanic). Muscle is the exception — customs carry muscle groups,
/// so they answer that chip.
struct CatalogFilterState: Equatable {
    // Exercises
    var muscle: MuscleGroup?
    var pattern: MovementPattern?
    var mechanic: ExerciseMechanic?
    var laterality: ExerciseLaterality?
    // Kit
    var equipmentCategory: SeedData.EquipmentCategory?
    // Routines
    var focus: RoutineTemplate.Focus?
    var effort: RoutineTemplate.Effort?
    var style: RoutineTemplate.Style?

    func isEmpty(for scope: FindScope) -> Bool {
        activeFacets(for: scope).isEmpty
    }

    /// The active facets for the summary popover, in the row's own order.
    func activeFacets(for scope: FindScope) -> [ActiveFacet] {
        switch scope {
        case .exercises:
            return [
                muscle.map { ActiveFacet(name: "Muscle", value: $0.displayName) },
                pattern.map { ActiveFacet(name: "Movement", value: $0.displayName) },
                mechanic.map { ActiveFacet(name: "Mechanic", value: $0.displayName) },
                laterality.map { ActiveFacet(name: "Sides", value: $0.displayName) },
            ].compactMap { $0 }
        case .kit:
            return [equipmentCategory.map { ActiveFacet(name: "Type", value: $0.rawValue) }].compactMap { $0 }
        case .routines:
            return [
                focus.map { ActiveFacet(name: "Focus", value: $0.rawValue) },
                effort.map { ActiveFacet(name: "Effort", value: $0.rawValue) },
                style.map { ActiveFacet(name: "Style", value: $0.rawValue) },
            ].compactMap { $0 }
        }
    }

    mutating func clear(scope: FindScope) {
        switch scope {
        case .exercises:
            muscle = nil; pattern = nil; mechanic = nil; laterality = nil
        case .kit:
            equipmentCategory = nil
        case .routines:
            focus = nil; effort = nil; style = nil
        }
    }

    // MARK: - Predicates (applied by FindOrCreateEngine before scoring)

    func allows(_ exercise: Exercise) -> Bool {
        if let muscle { guard exercise.muscleGroups.contains(muscle) else { return false } }
        if let pattern { guard exercise.movementPattern == pattern else { return false } }
        if let mechanic { guard exercise.mechanic == mechanic else { return false } }
        if let laterality { guard exercise.laterality == laterality else { return false } }
        return true
    }

    func allowsEquipment(named name: String) -> Bool {
        guard let equipmentCategory else { return true }
        return SeedData.equipmentCategory(named: name) == equipmentCategory
    }

    func allows(_ template: RoutineTemplate) -> Bool {
        if let focus { guard template.focus == focus else { return false } }
        if let effort { guard template.effort == effort else { return false } }
        if let style { guard template.style == style else { return false } }
        return true
    }

    /// A user routine answers Focus always (authored when template-born,
    /// else derived from what it trains — `focusLabel`'s exact rule);
    /// Effort/Style only resolve for template-born routines, so a
    /// hand-built routine drops out under those chips.
    func allows(_ routine: Routine) -> Bool {
        if let focus {
            let resolved = routine.catalogTemplate?.focus
                ?? RoutineTemplate.Focus.derived(fromMuscles: routine.muscleGroups, isCardio: routine.isCardio)
            guard resolved == focus else { return false }
        }
        if let effort { guard routine.catalogTemplate?.effort == effort else { return false } }
        if let style { guard routine.catalogTemplate?.style == style else { return false } }
        return true
    }
}
