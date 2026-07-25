import SwiftUI

/// What's left of the filter-row vocabulary (#237).
///
/// The chips themselves — `FacetChip`, `MultiFacetChip`, `TrayFilterChip`,
/// `FilterSummaryChip`, `SortChip`, `ActiveFacet` — are DELETED (2026-07-25).
/// Every surface that had a filter row lost it when the catalog tabs and the
/// search scopes became one view: the Exercises tab's Favorites and Muscle, the
/// equipment catalog's Kit facet, Type tray and Name/Most-exercises sort, and
/// the picker's Muscle/Equipment/Favorites bar all went at once. Dave's call —
/// the three catalogs read alike now, narrowed only by the search field, which
/// already scores muscle groups and equipment categories. Nothing in the app
/// filters by facet any more, so the controls that did it are in git history
/// rather than in the binary.
///
/// The SHAPE outlives them, because it isn't about filtering: it's the rule
/// that every interactive key in the app is a rounded rectangle at one radius
/// (Dave, 2026-07-20 — the r11 raised keys, the header icon squares), so shape
/// carries role, rounded-rect = control vs the capsule `CardTagCapsule` = inert
/// data tag. A dozen call sites still lean on it.
enum FilterChipShape {
    static let cornerRadius: CGFloat = Theme.keyRadius
}
