import Foundation
import SwiftData
import PlusPlusKit

/// What the Find-or-create surface is looking at. These are the app's three
/// CATALOG tabs — the ones the expanding search field absorbs, which then
/// ride above it as the scope row (2026-07-25). Today is deliberately absent:
/// it is a tab, never a scope (it holds a timeline of derived state, not a
/// list of typed items), so it keeps its place beside the field instead.
/// The former `.all` lens is gone with the browse index — cross-scope hits
/// are surfaced by the per-scope counts on the labels instead.
enum FindScope: String, CaseIterable {
    case routines, exercises, kit

    /// The scope's name, identical to the tab it was absorbed from — the
    /// control changes shape, never its vocabulary.
    var label: String {
        switch self {
        case .routines: return "Routines"
        case .exercises: return "Exercises"
        case .kit: return "Kit"
        }
    }

    var symbolName: String {
        switch self {
        case .routines: return "square.stack"
        case .exercises: return "list.bullet"
        case .kit: return "dumbbell"
        }
    }
}

/// Pure result collection for the Find-or-create surface: score, rank,
/// partition, section. No view state and no ModelContext — plain arrays
/// in, sections out — so the ranking rules are unit-testable without a
/// screen. The scoring mirrors the surfaces it replaced: exercises rank
/// over the name+muscle haystack (`ExerciseFilterState.searchHaystack`),
/// routines and templates deep-score name OR contained exercises at 0.75
/// (the routine catalog's `searchScore` rule), equipment over
/// name+category. One law throughout: YOURS BEFORE CATALOG.
enum FindOrCreateEngine {
    /// One hit. `mine` is both the top rank tier and the MINE/CATALOG
    /// group in scoped views: favorites + customs, your routines,
    /// active-kit equipment.
    struct Result: Identifiable {
        enum Item {
            case exercise(Exercise)
            case equipment(Equipment)
            case routine(Routine)
            case template(RoutineTemplate)
        }

        let item: Item
        let name: String
        let mine: Bool
        let score: Double
        /// Whether the active kit can do this item (all its equipment is in the
        /// kit). Drives the doable / "require more equipment" partition — the
        /// engine no longer HIDES un-doable rows, it groups them (2026-07-25).
        /// Equipment results are always `true` (a piece of gear isn't a thing
        /// you "do", so it's never in a missing group).
        let doable: Bool
        /// A routine/template matched only through an exercise it CONTAINS —
        /// carry the hit's name so the match explains itself ("has Bicep
        /// Curl" on a row whose own name says nothing about the query).
        let matchedExerciseName: String?
        let id: AnyHashable
    }

    struct Section: Identifiable {
        /// A normal results section, or the collapsible "N <noun>s require more
        /// equipment" group holding what the active kit can't do (2026-07-25).
        enum Kind: Equatable {
            case results
            case missing(noun: String)
        }

        let id: String
        /// ALL-CAPS section label stem for `.results`; the view appends " · n".
        /// Unused for `.missing` (the view builds the sentence from `count`).
        let title: String
        let count: Int
        let results: [Result]
        var kind: Kind = .results

        init(
            id: String? = nil,
            title: String,
            count: Int,
            results: [Result],
            kind: Kind = .results
        ) {
            self.id = id ?? title
            self.title = title
            self.count = count
            self.results = results
            self.kind = kind
        }
    }

    /// Which create verbs would COLLIDE with an item that already exists
    /// under the exact (case-insensitive, trimmed) name — one flag per
    /// creatable type. A create is suppressed when its type collides: the
    /// identical item is right there in the results to tap, so offering
    /// "Create/Add <name>" would only mint a duplicate (or read as new when
    /// it plainly isn't). A collision can never dead-end the surface — an
    /// exact-name match always ranks into results, so there is a row to tap.
    struct Collisions {
        var exercise = false
        var routine = false
        var equipment = false
    }

    /// Detect exact-name collisions for the current query. Routine covers
    /// both your routines AND catalog templates (one "routine" type on this
    /// surface). An empty query never collides.
    static func collisions(
        query: String,
        exercises: [Exercise],
        equipment: [Equipment],
        routines: [Routine],
        templates: [RoutineTemplate]
    ) -> Collisions {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return Collisions() }
        return Collisions(
            exercise: exercises.contains { !$0.isDeleted && $0.name.lowercased() == q },
            routine: routines.contains { !$0.isDeleted && $0.name.lowercased() == q }
                || templates.contains { $0.name.lowercased() == q },
            equipment: equipment.contains { !$0.isDeleted && $0.name.lowercased() == q }
        )
    }

    /// Results for the live query, within one scope. An empty query ranks
    /// EVERYTHING at score 0 (mine-first, then alphabetical) — that is the
    /// honest ranking answer, and it stays here so the ordering rules can be
    /// enumerated in tests. Whether a surface should ASK with an empty query is
    /// the surface's policy: `FindOrCreateView` doesn't (2026-07-25), because
    /// browsing a type belongs to that type's tab. A query narrows and ranks:
    /// mine-first, then score, then name.
    /// Nothing is HIDDEN by kit availability (2026-07-25): each routine/exercise
    /// scope splits into the doable rows, then a collapsible `.missing(noun:)`
    /// group of what the active kit can't do. Equipment is never partitioned
    /// (a piece of gear isn't a thing you "do").
    static func sections(
        query: String,
        scope: FindScope,
        exercises: [Exercise],
        equipment: [Equipment],
        routines: [Routine],
        templates: [RoutineTemplate],
        kitNames: Set<String>
    ) -> [Section] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        switch scope {
        case .routines:
            return groupedWithMissing(
                routineResults(q, routines: routines, templates: templates, kitNames: kitNames),
                noun: "routine"
            )
        case .exercises:
            return groupedWithMissing(
                exerciseResults(q, exercises: exercises, kitNames: kitNames),
                noun: "exercise"
            )
        case .kit:
            return grouped(equipmentResults(q, equipment: equipment, kitNames: kitNames))
        }
    }

    /// How many results each scope holds for the live query — the numbers the
    /// bottom bar paints beside the scope labels while searching. They are what
    /// replaced the retired All lens: a hit in a scope you aren't looking at is
    /// advertised by the very control that switches to it, so no cross-scope
    /// link rows are needed in the list. An empty query counts nothing, so the
    /// labels stay bare until there's something to count.
    static func matchCounts(
        query: String,
        exercises: [Exercise],
        equipment: [Equipment],
        routines: [Routine],
        templates: [RoutineTemplate],
        kitNames: Set<String>
    ) -> [FindScope: Int] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [:] }
        return [
            .routines: routineResults(q, routines: routines, templates: templates, kitNames: kitNames).count,
            .exercises: exerciseResults(q, exercises: exercises, kitNames: kitNames).count,
            .kit: equipmentResults(q, equipment: equipment, kitNames: kitNames).count
        ]
    }

    /// The scoped view's two groups. MINE = yours; CATALOG = everything
    /// else. Either group drops out when empty rather than showing a
    /// zero-count header.
    private static func grouped(_ results: [Result]) -> [Section] {
        let mine = results.filter(\.mine)
        let catalog = results.filter { !$0.mine }
        var sections: [Section] = []
        if !mine.isEmpty {
            sections.append(Section(title: "MINE", count: mine.count, results: mine))
        }
        if !catalog.isEmpty {
            sections.append(Section(title: "CATALOG", count: catalog.count, results: catalog))
        }
        return sections
    }

    /// Scoped Routines/Exercises: the doable rows grouped MINE/CATALOG, then a
    /// single collapsible `.missing(noun:)` group holding everything the kit
    /// can't do (mine-first ranked, uncapped — the whole point is to reveal it).
    private static func groupedWithMissing(_ results: [Result], noun: String) -> [Section] {
        var sections = grouped(results.filter(\.doable))
        let missing = results.filter { !$0.doable }
        if !missing.isEmpty {
            sections.append(Section(
                id: "MISSING",
                title: "MISSING",
                count: missing.count,
                results: missing,
                kind: .missing(noun: noun)
            ))
        }
        return sections
    }

    // MARK: - Per-type collection

    private static func rank(_ results: [Result]) -> [Result] {
        results.sorted { a, b in
            if a.mine != b.mine { return a.mine }
            if a.score != b.score { return a.score > b.score }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private static func exerciseResults(_ q: String, exercises: [Exercise], kitNames: Set<String>) -> [Result] {
        rank(exercises.compactMap { exercise in
            guard !exercise.isDeleted else { return nil }
            let score: Double
            if q.isEmpty {
                score = 0
            } else if let s = FuzzySearch.score(query: q, candidate: ExerciseFilterState.searchHaystack(exercise)) {
                score = s
            } else {
                return nil
            }
            return Result(
                item: .exercise(exercise),
                name: exercise.name,
                mine: exercise.isFavorite || !exercise.isBuiltIn,
                score: score,
                doable: ExerciseFilterState.missingEquipment(for: exercise, available: kitNames).isEmpty,
                matchedExerciseName: nil,
                id: AnyHashable(exercise.persistentModelID)
            )
        })
    }

    private static func equipmentResults(_ q: String, equipment: [Equipment], kitNames: Set<String>) -> [Result] {
        rank(equipment.compactMap { item in
            guard !item.isDeleted else { return nil }
            let category = SeedData.equipmentCategory(named: item.name)?.rawValue ?? ""
            let score: Double
            if q.isEmpty {
                score = 0
            } else if let s = FuzzySearch.score(query: q, candidate: "\(item.name) \(category)") {
                score = s
            } else {
                return nil
            }
            return Result(
                item: .equipment(item),
                name: item.name,
                mine: kitNames.contains(item.name),
                score: score,
                doable: true,
                matchedExerciseName: nil,
                id: AnyHashable(item.persistentModelID)
            )
        })
    }

    private static func routineResults(
        _ q: String,
        routines: [Routine],
        templates: [RoutineTemplate],
        kitNames: Set<String>
    ) -> [Result] {
        var results: [Result] = []
        for routine in routines where !routine.isDeleted {
            let contained = routine.sortedGroups.flatMap(\.sortedExercises).compactMap { $0.exercise?.name }
            guard let (score, matched) = deepScore(q, name: routine.name, contained: contained, extra: "") else { continue }
            let doable = routine.gearAvailability(activeNames: kitNames).allSatisfy(\.available)
            results.append(Result(
                item: .routine(routine),
                name: routine.name,
                mine: true,
                score: score,
                doable: doable,
                matchedExerciseName: matched,
                id: AnyHashable(routine.persistentModelID)
            ))
        }
        // An added template leaves CATALOG (name-keyed, the routine
        // catalog's rule): its routine row above already represents it.
        // A deleted routine does NOT shadow a template — its own row is
        // filtered out just above, so shadowing here would strand the
        // template with no row at all (matching the routine loop's filter
        // also closes the exact-name collision dead-end, swift-reviewer).
        let inLibrary = Set(routines.filter { !$0.isDeleted }.map { $0.name.lowercased() })
        for template in templates where !inLibrary.contains(template.name.lowercased()) {
            let contained = template.blocks.flatMap(\.entries).map(\.exercise)
            let extra = "\(template.summary) \(template.style.rawValue)"
            guard let (score, matched) = deepScore(q, name: template.name, contained: contained, extra: extra) else { continue }
            let doable = template.equipmentNames.allSatisfy { kitNames.contains($0) }
            results.append(Result(
                item: .template(template),
                name: template.name,
                mine: false,
                score: score,
                doable: doable,
                matchedExerciseName: matched,
                id: AnyHashable("template-\(template.name)")
            ))
        }
        return rank(results)
    }

    /// The routine-family score: the name is the headline; a hit anywhere
    /// else (contained exercises, a template's summary/style) still shows
    /// the row, demoted to 0.75 (the routine catalog's `searchScore`).
    /// When ONLY the deep haystack hit and a contained exercise matches
    /// the query, its name rides along for the "has X" capsule.
    private static func deepScore(
        _ q: String, name: String, contained: [String], extra: String
    ) -> (score: Double, matched: String?)? {
        guard !q.isEmpty else { return (0, nil) }
        let nameScore = FuzzySearch.score(query: q, candidate: name)
        let deep = "\(name) \(contained.joined(separator: " ")) \(extra)"
        let deepScore = FuzzySearch.score(query: q, candidate: deep).map { $0 * 0.75 }
        guard let best = [nameScore, deepScore].compactMap({ $0 }).max() else { return nil }
        let matched = nameScore == nil
            ? contained.first { FuzzySearch.matches(query: q, candidate: $0) }
            : nil
        return (best, matched)
    }
}
