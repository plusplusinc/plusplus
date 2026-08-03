import Foundation

/// What ONE absent piece of equipment would open.
///
/// The kit is a precise, declared constraint, and every exercise carries its
/// requirements — so for any piece the kit does not hold, the number of
/// exercises it alone stands between you and is a pure function over data
/// the app has always had. That number orders the Kit tab's catalog tier and
/// states itself on each row (#251), and it is the same number the equipment
/// screen's "+N" add beat plays.
///
/// Pure value math over `ExerciseSimilarityFeatures` — the bag the swap
/// ranker already builds — so it is Linux-tested and the CLI can reach it.
///
/// ⚠️ Renamed from `CatalogReachCalculator` on 2026-08-03, when the catalog
/// front matter that needed the rest of that type was removed. What is left
/// is this one question, and the file is named for it.
public enum KitUnlocks {

    /// Keyed by equipment NAME, the identity the kit matches on everywhere.
    ///
    /// ⚠️ The count is MARGINAL and truthful, never "everything that uses
    /// this". A piece that is one of TWO things a move is missing scores
    /// nothing for that move until the other arrives, so the numbers never
    /// overclaim — and a number that overclaims on the surface you use to
    /// decide what to buy is worse than no number. Pieces already in the kit
    /// are ABSENT from the map: they cannot open anything, and a zero would
    /// invite a caller to print one.
    ///
    /// ⚠️ Single pieces only. A bench and a barbell together are worth more
    /// than the sum of their entries, and nothing here says so — stating
    /// that would make this a solver rather than a fact.
    public static func byPiece(
        _ catalog: [ExerciseSimilarityFeatures],
        kit: Set<String>
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for features in catalog {
            let missing = features.equipmentNames.subtracting(kit)
            // Exactly one thing in the way: that piece is what opens it.
            guard missing.count == 1, let only = missing.first else { continue }
            counts[only, default: 0] += 1
        }
        return counts
    }
}
