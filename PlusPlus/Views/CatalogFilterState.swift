import Foundation
import PlusPlusKit

/// One active facet, named for the summary popover ("Muscle · Chest").
struct ActiveFacet: Identifiable, Equatable {
    let name: String
    let value: String
    var id: String { name }
}

/// The coarse KIND of thing an exercise is — the one axis the catalog
/// genuinely cannot be searched for (from the cardio push, #475; rebuilt
/// on the returned facet row's grammar when the two landed together).
///
/// Every cardio exercise is filed under the `fullBody` muscle group, so
/// in a catalog that is ninety percent lifting no other facet reaches
/// the cardio rows as a set, and search only helps once you already
/// know a name. Three buckets, not twelve: the modality families are
/// the right granularity for a Health activity type and the wrong one
/// for a filter Menu, where "Cycling" and "Indoor cycling" as separate
/// options would be noise. Collapsing them is safe because
/// `ExerciseModality.isCardio` already draws the only line that
/// matters here.
enum CatalogKind: String, CaseIterable, Hashable {
    case cardio
    case strength
    case mobility

    init(_ modality: ExerciseModality) {
        switch modality {
        case .flexibility: self = .mobility
        default: self = modality.isCardio ? .cardio : .strength
        }
    }

    var label: String {
        switch self {
        case .cardio: "Cardio"
        case .strength: "Strength"
        case .mobility: "Mobility"
        }
    }
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
/// ⚠️ Multi-select facets are SETS (#498), and the composition rule is
/// the standard one: OR inside a facet, AND across them — "chest or
/// shoulders, and compound". An EMPTY set means the facet is off, never
/// "match nothing". The two binary facets stay single-select optionals:
/// picking both `compound` and `isolation` says exactly what picking
/// neither says, so a set there would be ceremony around a toggle.
struct CatalogFilterState: Equatable {
    // Exercises. Kind leads: it is the coarsest axis, and the one the
    // row exists for (nothing else reaches cardio as a set).
    var kinds: Set<CatalogKind> = []
    var muscles: Set<MuscleGroup> = []
    var patterns: Set<MovementPattern> = []
    var mechanic: ExerciseMechanic?
    var laterality: ExerciseLaterality?
    // Kit
    var equipmentCategories: Set<SeedData.EquipmentCategory> = []
    // Routines
    var focuses: Set<RoutineTemplate.Focus> = []
    var efforts: Set<RoutineTemplate.Effort> = []
    var styles: Set<RoutineTemplate.Style> = []

    func isEmpty(for scope: FindScope) -> Bool {
        activeFacets(for: scope).isEmpty
    }

    /// One active facet's value text: the value when there is one, all of
    /// them when there are several — the summary popover names what is
    /// on, and a bare count there would just move the question.
    private static func facet<Value>(_ name: String, _ values: Set<Value>, _ display: (Value) -> String) -> ActiveFacet? {
        guard !values.isEmpty else { return nil }
        return ActiveFacet(name: name, value: values.map(display).sorted().joined(separator: ", "))
    }

    /// The active facets for the summary popover, in the row's own order.
    func activeFacets(for scope: FindScope) -> [ActiveFacet] {
        switch scope {
        case .exercises:
            return [
                Self.facet("Kind", kinds) { $0.label },
                Self.facet("Muscle", muscles) { $0.displayName },
                Self.facet("Movement", patterns) { $0.displayName },
                mechanic.map { ActiveFacet(name: "Mechanic", value: $0.displayName) },
                laterality.map { ActiveFacet(name: "Sides", value: $0.displayName) },
            ].compactMap { $0 }
        case .kit:
            return [Self.facet("Type", equipmentCategories) { $0.rawValue }].compactMap { $0 }
        case .routines:
            return [
                Self.facet("Focus", focuses) { $0.rawValue },
                Self.facet("Effort", efforts) { $0.rawValue },
                Self.facet("Style", styles) { $0.rawValue },
            ].compactMap { $0 }
        }
    }

    mutating func clear(scope: FindScope) {
        switch scope {
        case .exercises:
            kinds = []; muscles = []; patterns = []; mechanic = nil; laterality = nil
        case .kit:
            equipmentCategories = []
        case .routines:
            focuses = []; efforts = []; styles = []
        }
    }

    // MARK: - Predicates (applied by FindOrCreateEngine before scoring)

    func allows(_ exercise: Exercise) -> Bool {
        // Every exercise has a modality, so Kind is the one facet nothing
        // ever drops out under — customs included.
        if !kinds.isEmpty { guard kinds.contains(CatalogKind(exercise.modality)) else { return false } }
        if !muscles.isEmpty { guard !muscles.isDisjoint(with: Set(exercise.muscleGroups)) else { return false } }
        if !patterns.isEmpty {
            guard let pattern = exercise.movementPattern, patterns.contains(pattern) else { return false }
        }
        if let mechanic { guard exercise.mechanic == mechanic else { return false } }
        if let laterality { guard exercise.laterality == laterality else { return false } }
        return true
    }

    func allowsEquipment(named name: String) -> Bool {
        guard !equipmentCategories.isEmpty else { return true }
        guard let category = SeedData.equipmentCategory(named: name) else { return false }
        return equipmentCategories.contains(category)
    }

    func allows(_ template: RoutineTemplate) -> Bool {
        if !focuses.isEmpty { guard focuses.contains(template.focus) else { return false } }
        if !efforts.isEmpty { guard efforts.contains(template.effort) else { return false } }
        if !styles.isEmpty { guard styles.contains(template.style) else { return false } }
        return true
    }

    /// A user routine answers Focus always (authored when template-born,
    /// else derived from what it trains — `focusLabel`'s exact rule);
    /// Effort/Style only resolve for template-born routines, so a
    /// hand-built routine drops out under those chips.
    func allows(_ routine: Routine) -> Bool {
        if !focuses.isEmpty { guard focuses.contains(resolvedFocus(routine)) else { return false } }
        if !efforts.isEmpty {
            guard let effort = routine.catalogTemplate?.effort, efforts.contains(effort) else { return false }
        }
        if !styles.isEmpty {
            guard let style = routine.catalogTemplate?.style, styles.contains(style) else { return false }
        }
        return true
    }

    /// Every routine can answer Focus: authored when template-born,
    /// derived from what it trains otherwise (`focusLabel`'s exact rule).
    ///
    /// Static and internal since 2026-08-02: the catalog's front matter
    /// buckets routines by focus and has to bucket them the way the facet
    /// narrows them, or the chip's count and the list it opens disagree.
    static func resolvedFocus(_ routine: Routine) -> RoutineTemplate.Focus {
        routine.catalogTemplate?.focus
            ?? RoutineTemplate.Focus.derived(fromMuscles: routine.muscleGroups, isCardio: routine.isCardio)
    }

    private func resolvedFocus(_ routine: Routine) -> RoutineTemplate.Focus {
        Self.resolvedFocus(routine)
    }

    /// The same test with the two RATING facets skipped — what decides
    /// whether a hand-built routine surfaces as "not rated" rather than
    /// vanishing (#507, Q14-A). It still has to clear Focus, which every
    /// routine can answer (authored when template-born, derived
    /// otherwise), so this only ever forgives the two facets that
    /// resolve through `catalogTemplate`.
    func allowsIgnoringRating(_ routine: Routine) -> Bool {
        guard !efforts.isEmpty || !styles.isEmpty else { return false }
        if !focuses.isEmpty { guard focuses.contains(resolvedFocus(routine)) else { return false } }
        // A template-born routine CAN answer effort/style; if it got here
        // it genuinely failed them, so it stays out.
        return routine.catalogTemplate == nil
    }
}
