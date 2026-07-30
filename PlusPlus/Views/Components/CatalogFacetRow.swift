import SwiftUI
import PlusPlusKit

/// The coarse KIND of thing an exercise is — the one axis the catalog
/// genuinely cannot be searched for.
///
/// Three buckets, not twelve: the modality families are the right
/// granularity for a Health activity type and the wrong one for a filter
/// row, where "Cycling" and "Indoor cycling" as separate chips would be
/// noise. Collapsing them is safe because `ExerciseModality.isCardio`
/// already draws the only line that matters here.
enum CatalogKind: String, CaseIterable, Identifiable, Hashable {
    case cardio
    case strength
    case mobility

    var id: String { rawValue }

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

    /// The tab bar's own symbols would be wrong here (these are content
    /// types, not destinations), so each takes the figure its family
    /// already wears on a search row.
    var symbolName: String {
        switch self {
        case .cardio: "figure.run"
        case .strength: "figure.strengthtraining.traditional"
        case .mobility: "figure.flexibility"
        }
    }
}

/// The exercise catalog's filter rack.
///
/// ⚠️ This reverses the 2026-07-25 retirement, deliberately and only for
/// the Exercises surface (Dave, 2026-07-30). The chips came off on the
/// reasoning that "the search field reaches what the chips reached" —
/// true of Favorites and Muscle, and false of KIND. Every cardio exercise
/// is filed under the `fullBody` muscle group, so in a catalog that is
/// ninety percent lifting there was no word that reached the cardio rows
/// as a set, and search only helps once you already know one. Modality
/// joins the search haystack in the same change; this is the half for
/// people who don't know what to type.
///
/// Grammar: `SelectableChip` throughout, so selection reads as the app's
/// one selection look (tinted ground, ring, bright ink). The summary chip
/// follows the 2026-07-23 rule that active filters SUMMARIZE rather than
/// insta-clear — it states the count and holds the Clear.
struct CatalogFacetRow: View {
    @Binding var kinds: Set<CatalogKind>
    @Binding var favoritesOnly: Bool
    @Binding var muscles: Set<MuscleGroup>
    /// Opens the muscle multi-select. A pushed list, never a menu — eleven
    /// groups is more than a chip row can hold, and the multi-select law
    /// says a list.
    let onPickMuscles: () -> Void

    private var activeCount: Int {
        kinds.count + muscles.count + (favoritesOnly ? 1 : 0)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CatalogKind.allCases) { kind in
                    SelectableChip(
                        label: kind.label,
                        isSelected: kinds.contains(kind),
                        identifier: "facetKind-\(kind.rawValue)",
                        systemImage: kind.symbolName
                    ) {
                        if kinds.contains(kind) { kinds.remove(kind) } else { kinds.insert(kind) }
                    }
                }

                SelectableChip(
                    label: "Favorites",
                    isSelected: favoritesOnly,
                    identifier: "facetFavorites",
                    systemImage: "star.fill"
                ) {
                    favoritesOnly.toggle()
                }

                SelectableChip(
                    label: muscleLabel,
                    isSelected: !muscles.isEmpty,
                    identifier: "facetMuscle",
                    systemImage: "figure.arms.open"
                ) {
                    onPickMuscles()
                }

                if activeCount > 0 {
                    // Clear is a quiet escape, not a selectable state — the
                    // escape-hatch grammar, and the reason it isn't another
                    // SelectableChip.
                    QuietKey(label: "Clear", identifier: "facetClear") {
                        kinds.removeAll()
                        muscles.removeAll()
                        favoritesOnly = false
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// "Muscle" at rest, the group's own name when exactly one is on, a
    /// count beyond that — a chip that just said "Muscle" while three were
    /// active would hide its own state.
    private var muscleLabel: String {
        switch muscles.count {
        case 0: "Muscle"
        case 1: muscles.first?.displayName ?? "Muscle"
        default: "Muscle · \(muscles.count)"
        }
    }
}
