import Foundation
import PlusPlusKit

/// Exercise-set arithmetic: what a kit is missing for a move, and which other
/// moves could stand in for it.
///
/// It used to hold the exercise catalog's and the picker's filter state — a
/// search string, favorites, muscle groups, equipment — hence the name. All of
/// that left on 2026-07-25; the facet state that RETURNED on 2026-07-31 lives
/// in `CatalogFilterState`, not here. So this is an `enum` now, which makes
/// "there is no state left" a thing the compiler enforces rather than a
/// comment. The name is kept because it appears across half a dozen call
/// sites and every rename is a diff nobody reads; the next person to touch
/// this file should feel free to rename it.
enum ExerciseFilterState {

    /// Name, EVERY muscle group it works, the words its movement family
    /// goes by, the movement pattern's display name, and the hidden
    /// synonym terms. One haystack, one scoring pass; highlighting stays
    /// name-only, and an unhighlighted row reads fine.
    ///
    /// Muscles are why "hamstring curl" finds Leg Curl even though no
    /// exercise carries the word "hamstring" in its name, and "triceps"
    /// finds Bench Press even though it's filed under chest.
    ///
    /// Modality is why "cardio" finds anything at all. Every cardio
    /// exercise is filed under the `fullBody` muscle group, so before this
    /// the catalog offered no word that reached the cardio rows as a set —
    /// you had to already know the app called it "Rowing" and not "erg".
    /// Now "cardio", "run", "bike", "row", "hike" and "swim" all land.
    ///
    /// Pattern is why "hinge" finds the deadlifts (2026-07-31, #494), and
    /// the synonyms ("rdl", "tgu" — `CatalogSearchSynonyms`) carry the
    /// gym slang the names don't.
    static func searchHaystack(_ exercise: Exercise) -> String {
        var parts = [exercise.name]
            + exercise.muscleGroups.map(\.displayName)
            + exercise.modality.searchTerms
        if let pattern = exercise.movementPattern { parts.append(pattern.displayName) }
        let synonyms = CatalogSearchSynonyms.exerciseTerms(named: exercise.name)
        if !synonyms.isEmpty { parts.append(synonyms) }
        return parts.joined(separator: " ")
    }

    /// Equipment the exercise needs but the given set doesn't have — drives the
    /// "require more equipment" grouping and the "needs squat rack" cue.
    static func missingEquipment(for exercise: Exercise, available: Set<String>) -> [String] {
        // isDeleted: a just-deleted custom equipment lingers in the
        // relationship until save and must not count as available or
        // missing (bug hunt B1).
        exercise.equipment.filter { !$0.isDeleted && !available.contains($0.name) }.map(\.name).sorted()
    }

    /// Catalog exercises that hit the same PRIMARY muscle group as
    /// `exercise` and are doable with the given kit — the substitution pool
    /// for the equipment resolve sheet's "swap the moves" step
    /// (2026-07-22). ⚠️ Deliberately still the primary alone, now that an
    /// exercise carries several (2026-07-28): this list is sorted by NAME,
    /// with no similarity ranking to keep quality up, so widening it to
    /// "shares any group" would seat a triceps pushdown among the offered
    /// replacements for a bench press. It reads as "another <muscle> move
    /// your kit can do". `swapSuggestions` below, which IS ranked, does
    /// widen. The exercise itself and any just-deleted straggler drop out.
    static func kitDoableAlternatives(for exercise: Exercise, in catalog: [Exercise], kit: Set<String>) -> [Exercise] {
        catalog.filter { candidate in
            candidate !== exercise
                && !candidate.isDeleted
                && candidate.muscleGroup == exercise.muscleGroup
                && missingEquipment(for: candidate, available: kit).isEmpty
        }
        .sorted { $0.name < $1.name }
    }

    /// Ranked substitution suggestions for the "Swap for…" tray (2026-07-24):
    /// same-muscle catalog moves ordered kit-doable-first, then by
    /// similarity to the origin (movement family + gear overlap, the
    /// `ExerciseSimilarity` ranker), then alphabetically. The pool is any
    /// move SHARING A GROUP (2026-07-28, when exercises gained several):
    /// a dip is a real bench-press substitute and used to be invisible
    /// here because it files under triceps. Widening is safe precisely
    /// because this list is ranked — the ranker weights the primary
    /// heavily, so shares-a-secondary-only moves sort to the bottom rather
    /// than displacing the obvious swaps.
    /// Unlike `kitDoableAlternatives` this never gear-HIDES:
    /// not-in-kit moves stay, ranked below the doable ones and flagged amber
    /// on the row (#113 flag-don't-hide). The origin and just-deleted
    /// stragglers drop out. The full catalog is one tap further (the tray's
    /// "Browse all exercises" escape).
    static func swapSuggestions(for exercise: Exercise, in catalog: [Exercise], kit: Set<String>) -> [Exercise] {
        let origin = similarityFeatures(exercise)
        let originGroups = Set(exercise.muscleGroups)
        let pool = catalog
            .filter { $0 !== exercise && !$0.isDeleted && !originGroups.isDisjoint(with: $0.muscleGroups) }
            .sorted { $0.name < $1.name }
        // Stable, kit-doable-first partition; each half stays similarity-ranked
        // (the ranker's tie-break preserves the alphabetical incoming order).
        let doable = pool.filter { missingEquipment(for: $0, available: kit).isEmpty }
        let rest = pool.filter { !missingEquipment(for: $0, available: kit).isEmpty }
        let rank = { (list: [Exercise]) in
            ExerciseSimilarity.ranked(list, like: origin, features: similarityFeatures)
        }
        return rank(doable) + rank(rest)
    }

    /// Maps an `Exercise` into the Kit ranker's pure feature bag. The two
    /// authored attributes ride along (#495); a row that carries neither
    /// is not penalized for it — the ranker renormalizes over what it can
    /// actually compare.
    ///
    /// Internal since 2026-08-02: the catalog's front matter counts reach
    /// over the same bag (`CatalogReachCalculator`), and a second mapper
    /// would be a second reading of what an exercise requires.
    static func similarityFeatures(_ exercise: Exercise) -> ExerciseSimilarityFeatures {
        ExerciseSimilarityFeatures(
            muscleGroups: exercise.muscleGroups,
            modality: exercise.modality,
            equipmentNames: Set(exercise.equipment.filter { !$0.isDeleted }.map(\.name)),
            movementPattern: exercise.movementPattern,
            mechanic: exercise.mechanic
        )
    }
}
