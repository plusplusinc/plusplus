import Foundation
import SwiftData
import PlusPlusKit

/// What the Find-or-create surface is looking at — the scope chips' four
/// lenses (2026-07-23 handoff). Raw values feed a11y identifiers only.
enum FindScope: String, CaseIterable {
    case all, routines, exercises, kit
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
        /// A routine/template matched only through an exercise it CONTAINS —
        /// carry the hit's name so the match explains itself ("has Bicep
        /// Curl" on a row whose own name says nothing about the query).
        let matchedExerciseName: String?
        let id: AnyHashable
    }

    struct Section: Identifiable {
        /// ALL-CAPS section label stem; the view appends " · n".
        let title: String
        let count: Int
        /// Set on All-scope sections: the header AND the more-row jump here.
        let scopeTarget: FindScope?
        let results: [Result]
        /// Rows folded behind "n more ›" (All scope caps each type).
        let moreCount: Int
        var id: String { title }
    }

    /// All-scope sections show this many rows before folding into "n more ›".
    static let allScopeCap = 3

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

    /// An EMPTY query shows everything (no blank state): every item at
    /// score 0, mine-first then alphabetical. A query narrows and ranks:
    /// mine-first, then score, then name.
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
        case .all:
            let sections: [(String, FindScope, [Result])] = [
                ("ROUTINES", .routines, routineResults(q, routines: routines, templates: templates, kitNames: kitNames)),
                ("EXERCISES", .exercises, exerciseResults(q, exercises: exercises)),
                ("EQUIPMENT", .kit, equipmentResults(q, equipment: equipment, kitNames: kitNames)),
            ]
            return sections.compactMap { title, target, results in
                guard !results.isEmpty else { return nil }
                return Section(
                    title: title,
                    count: results.count,
                    scopeTarget: target,
                    results: Array(results.prefix(allScopeCap)),
                    moreCount: max(0, results.count - allScopeCap)
                )
            }
        case .routines:
            return grouped(routineResults(q, routines: routines, templates: templates, kitNames: kitNames))
        case .exercises:
            return grouped(exerciseResults(q, exercises: exercises))
        case .kit:
            return grouped(equipmentResults(q, equipment: equipment, kitNames: kitNames))
        }
    }

    /// The scoped view's two groups. MINE = yours; CATALOG = everything
    /// else. Either group drops out when empty rather than showing a
    /// zero-count header.
    private static func grouped(_ results: [Result]) -> [Section] {
        let mine = results.filter(\.mine)
        let catalog = results.filter { !$0.mine }
        var sections: [Section] = []
        if !mine.isEmpty {
            sections.append(Section(title: "MINE", count: mine.count, scopeTarget: nil, results: mine, moreCount: 0))
        }
        if !catalog.isEmpty {
            sections.append(Section(title: "CATALOG", count: catalog.count, scopeTarget: nil, results: catalog, moreCount: 0))
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

    private static func exerciseResults(_ q: String, exercises: [Exercise]) -> [Result] {
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
            results.append(Result(
                item: .routine(routine),
                name: routine.name,
                mine: true,
                score: score,
                matchedExerciseName: matched,
                id: AnyHashable(routine.persistentModelID)
            ))
        }
        // An added template leaves CATALOG (name-keyed, the routine
        // catalog's rule): its routine row above already represents it.
        let inLibrary = Set(routines.map { $0.name.lowercased() })
        for template in templates where !inLibrary.contains(template.name.lowercased()) {
            let contained = template.blocks.flatMap(\.entries).map(\.exercise)
            let extra = "\(template.summary) \(template.style.rawValue)"
            guard let (score, matched) = deepScore(q, name: template.name, contained: contained, extra: extra) else { continue }
            results.append(Result(
                item: .template(template),
                name: template.name,
                mine: false,
                score: score,
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
