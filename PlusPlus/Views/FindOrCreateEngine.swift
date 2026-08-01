import Foundation
import SwiftData
import PlusPlusKit

/// What the Find-or-create surface is looking at. These are the app's three
/// CATALOG tabs — the ones the search field absorbs when it takes over the tab
/// bar, which then ride above it as the accessory scope row (2026-07-25).
/// Today is deliberately absent: it is a tab, never a scope (it holds a
/// timeline of derived state, not a list of typed items, so there is nothing
/// in it to narrow). The former `.all` lens is gone — a scope with no query
/// now shows its whole list, and cross-scope hits are surfaced by the
/// per-scope counts on the labels.
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

    /// What this scope SEARCHES, which is not always what the tab is called:
    /// the Kit scope searches the whole equipment catalog, not just your kit,
    /// so it takes the single-item/catalog word (the kit-vs-equipment
    /// vocabulary law). Used for prompts and empty states, never as a label.
    var searchNoun: String {
        switch self {
        case .routines: return "routines"
        case .exercises: return "exercises"
        case .kit: return "equipment"
        }
    }

    /// The same noun, counted — "1 routine", "3 exercises", and
    /// "equipment" either way (it is already a mass noun, the kit-vs-
    /// equipment vocabulary law). For the hidden-by-filters row (#507).
    func searchNoun(for count: Int) -> String {
        switch self {
        case .routines: return count == 1 ? "routine" : "routines"
        case .exercises: return count == 1 ? "exercise" : "exercises"
        case .kit: return "equipment"
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
        /// False only for a hand-built routine surfacing under an
        /// Effort/Style facet it cannot answer (#507, Q14-A) — those
        /// group under "not rated" instead of vanishing. True for
        /// everything else, so no other call site changes.
        var rated: Bool = true
    }

    /// One pass's whole answer: what to draw, and what the facets are
    /// holding back for the same query (#507, Q13-A).
    struct Outcome {
        let sections: [Section]
        /// Query matches excluded by an active facet — the rows the
        /// "N hidden by filters" key offers to bring back. Zero when no
        /// facet is on, since nothing can then be hiding anything.
        let hiddenByFilters: Int
    }

    struct Section: Identifiable {
        /// A normal results section, or the collapsible "N <noun>s require more
        /// equipment" group holding what the active kit can't do (2026-07-25).
        enum Kind: Equatable {
            case results
            case missing(noun: String)
            /// Hand-built routines under an Effort or Style facet (#507,
            /// Q14-A). Those two resolve only through `catalogTemplate`,
            /// so a from-scratch library EMPTIED under them — the
            /// flag-don't-hide law's own failure, in a corner nobody
            /// looked at. Same disclosure shape as `.missing`: narrowed,
            /// never vanished.
            case unrated
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

    /// Results for the live query, within one scope. This is the ONE list each
    /// catalog surface shows (2026-07-25): with no query it IS the tab's list —
    /// everything, mine-first, in the caller's own order (so a user's routine
    /// ordering survives) — and a query narrows and ranks it: mine-first, then
    /// score, then name. Same view either way; the field only filters.
    /// Nothing is HIDDEN by kit availability (2026-07-25): each routine/exercise
    /// scope splits into the doable rows, then a collapsible `.missing(noun:)`
    /// group of what the active kit can't do. Equipment is never partitioned
    /// (a piece of gear isn't a thing you "do").
    /// `filters` and the query AND-compose — the filter decides who
    /// competes, the query ranks them (facet chips, 2026-07-31). The
    /// missing-equipment partition runs after filtering, unchanged (kit
    /// availability is still not a filter), and `collisions` never sees
    /// filters (creation is unaffected by narrowing).
    static func sections(
        query: String,
        scope: FindScope,
        filters: CatalogFilterState = CatalogFilterState(),
        exercises: [Exercise],
        equipment: [Equipment],
        routines: [Routine],
        templates: [RoutineTemplate],
        kitNames: Set<String>
    ) -> [Section] {
        outcome(
            query: query, scope: scope, filters: filters,
            exercises: exercises, equipment: equipment,
            routines: routines, templates: templates, kitNames: kitNames
        ).sections
    }

    /// The sections PLUS how many query matches the active facets kept
    /// off the screen — both from ONE pass (#507, Q13-A).
    ///
    /// ⚠️ The count has to be free, and that is what fixes the order of
    /// operations here: each candidate is SCORED first and classified by
    /// facet second, so a hidden row is counted where it was already
    /// being examined. Deriving it instead as "unfiltered total minus
    /// shown" costs a second full ranking pass per keystroke — the exact
    /// cost the per-scope match counts were retired over (2026-07-25),
    /// and the reason `FilterSummaryChip`'s total used to be a closure.
    /// Output is unchanged by the reorder: scoring is per-item pure, so
    /// filtering before or after it yields the same set in the same
    /// order.
    static func outcome(
        query: String,
        scope: FindScope,
        filters: CatalogFilterState = CatalogFilterState(),
        exercises: [Exercise],
        equipment: [Equipment],
        routines: [Routine],
        templates: [RoutineTemplate],
        kitNames: Set<String>
    ) -> Outcome {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        switch scope {
        case .routines:
            let pass = routineResults(q, routines: routines, templates: templates, kitNames: kitNames, filters: filters)
            return Outcome(
                sections: groupedWithMissing(pass.results, noun: "routine"),
                hiddenByFilters: pass.hidden
            )
        case .exercises:
            let pass = exerciseResults(q, exercises: exercises, kitNames: kitNames, filters: filters)
            return Outcome(
                sections: groupedWithMissing(pass.results, noun: "exercise"),
                hiddenByFilters: pass.hidden
            )
        case .kit:
            let pass = equipmentResults(q, equipment: equipment, kitNames: kitNames, filters: filters)
            return Outcome(sections: grouped(pass.results), hiddenByFilters: pass.hidden)
        }
    }

    // The per-scope match COUNTS the bar paints beside its labels aren't
    // computed here any more (2026-07-25). Each scope's surface stays mounted
    // and already builds its own sections, so it publishes its own count by
    // summing them — a `matchCounts` here meant a second full ranking pass over
    // all three types on every keystroke, on top of the one the visible surface
    // was already running.

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

    /// Scoped Routines/Exercises: MINE then CATALOG, and **each** tier carries
    /// its own collapsible `.missing(noun:)` subgroup for what the active kit
    /// can't do (Dave, 2026-07-25). Keeping the split inside the tier means
    /// "yours that need more equipment" stays with the rest of yours instead of
    /// being pooled with the catalog's at the bottom — the MINE/CATALOG
    /// division is the primary one, kit availability the secondary.
    /// A tier drops out entirely when it has nothing, in either half.
    private static func groupedWithMissing(_ results: [Result], noun: String) -> [Section] {
        var sections: [Section] = []
        // Unrated rows (#507, Q14-A) leave the tiers entirely and group
        // once at the end: they are not a narrower slice of MINE, they
        // are the rows the active facet has no opinion about, and
        // splitting them per tier would print the disclosure twice for
        // a distinction only hand-built routines can have.
        let rated = results.filter(\.rated)
        let unrated = results.filter { !$0.rated }
        for (title, isMine) in [("MINE", true), ("CATALOG", false)] {
            let tier = rated.filter { $0.mine == isMine }
            let doable = tier.filter(\.doable)
            let missing = tier.filter { !$0.doable }
            if !doable.isEmpty {
                sections.append(Section(title: title, count: doable.count, results: doable))
            }
            if !missing.isEmpty {
                sections.append(Section(
                    id: "MISSING_\(title)",
                    title: title,
                    count: missing.count,
                    results: missing,
                    kind: .missing(noun: noun)
                ))
            }
        }
        if !unrated.isEmpty {
            sections.append(Section(
                id: "UNRATED",
                title: "MINE",
                count: unrated.count,
                results: unrated,
                kind: .unrated
            ))
        }
        return sections
    }

    // MARK: - Per-type collection

    /// Mine first, then best match, then name.
    ///
    /// With NO query this becomes a stable partition on `mine` alone, which
    /// preserves the caller's incoming order — and that order is meaningful:
    /// routines arrive in the user's own `Routine.order` (which drag-reorder
    /// writes), exercises and equipment arrive alphabetically from their
    /// queries. Re-sorting by name here would silently discard a user's
    /// routine ordering the moment their tab started rendering these sections.
    private static func rank(_ results: [Result], query: String) -> [Result] {
        guard !query.isEmpty else {
            return results.filter(\.mine) + results.filter { !$0.mine }
        }
        return results.sorted { a, b in
            if a.mine != b.mine { return a.mine }
            if a.score != b.score { return a.score > b.score }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private static func exerciseResults(_ q: String, exercises: [Exercise], kitNames: Set<String>, filters: CatalogFilterState = CatalogFilterState()) -> Pass {
        var hidden = 0
        let results = exercises.compactMap { exercise -> Result? in
            guard !exercise.isDeleted else { return nil }
            let score: Double
            if q.isEmpty {
                score = 0
            } else if let s = FuzzySearch.score(query: q, candidate: ExerciseFilterState.searchHaystack(exercise)) {
                score = s
            } else {
                return nil
            }
            // Scored, so it MATCHES — a facet dropping it now is the
            // filters hiding a match, which is exactly what gets counted.
            guard filters.allows(exercise) else { hidden += 1; return nil }
            return Result(
                item: .exercise(exercise),
                name: exercise.name,
                mine: exercise.isFavorite || !exercise.isBuiltIn,
                score: score,
                doable: ExerciseFilterState.missingEquipment(for: exercise, available: kitNames).isEmpty,
                matchedExerciseName: nil,
                id: AnyHashable(exercise.persistentModelID)
            )
        }
        return Pass(results: rank(results, query: q), hidden: hidden)
    }

    private static func equipmentResults(_ q: String, equipment: [Equipment], kitNames: Set<String>, filters: CatalogFilterState = CatalogFilterState()) -> Pass {
        var hidden = 0
        let results = equipment.compactMap { item -> Result? in
            guard !item.isDeleted else { return nil }
            let category = SeedData.equipmentCategory(named: item.name)?.rawValue ?? ""
            // Hidden synonym terms ride the same candidate ("erg" reaches
            // the Rowing Machine); customs contribute "" and lose nothing.
            let synonyms = CatalogSearchSynonyms.equipmentTerms(named: item.name)
            let score: Double
            if q.isEmpty {
                score = 0
            } else if let s = FuzzySearch.score(query: q, candidate: "\(item.name) \(category) \(synonyms)") {
                score = s
            } else {
                return nil
            }
            guard filters.allowsEquipment(named: item.name) else { hidden += 1; return nil }
            return Result(
                item: .equipment(item),
                name: item.name,
                mine: kitNames.contains(item.name),
                score: score,
                doable: true,
                matchedExerciseName: nil,
                id: AnyHashable(item.persistentModelID)
            )
        }
        return Pass(results: rank(results, query: q), hidden: hidden)
    }

    private static func routineResults(
        _ q: String,
        routines: [Routine],
        templates: [RoutineTemplate],
        kitNames: Set<String>,
        filters: CatalogFilterState = CatalogFilterState()
    ) -> Pass {
        var results: [Result] = []
        var hidden = 0
        for routine in routines where !routine.isDeleted {
            let contained = routine.sortedGroups.flatMap(\.sortedExercises).compactMap { $0.exercise?.name }
            guard let (score, matched) = deepScore(q, name: routine.name, contained: contained, extra: "") else { continue }
            // A hand-built routine can't answer Effort or Style (they
            // resolve only via `catalogTemplate`), so under those facets
            // it is UNRATED, not excluded — it still has to clear every
            // facet it CAN answer (#507, Q14-A). Only a routine that
            // fails a facet it COULD answer counts as hidden.
            let rated = filters.allows(routine)
            let unrated = !rated && filters.allowsIgnoringRating(routine)
            guard rated || unrated else { hidden += 1; continue }
            let doable = routine.gearAvailability(activeNames: kitNames).allSatisfy(\.available)
            results.append(Result(
                item: .routine(routine),
                name: routine.name,
                mine: true,
                score: score,
                doable: doable,
                matchedExerciseName: matched,
                id: AnyHashable(routine.persistentModelID),
                rated: !unrated
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
            // A template answers every routine facet, so a failure here
            // is always the filters hiding a match. (An in-library
            // template is NOT hidden — its own routine row represents
            // it, and that row is subject to the same facets.)
            guard filters.allows(template) else { hidden += 1; continue }
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
        return Pass(results: rank(results, query: q), hidden: hidden)
    }

    /// One type's collection pass: the rows, and the query matches its
    /// facets excluded (counted in the same sweep — see `outcome`).
    private struct Pass {
        let results: [Result]
        let hidden: Int
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
