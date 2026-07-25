import SwiftUI
import PlusPlusKit

/// The tab-root header grammar, shared by every catalog surface: the ++ key,
/// the large on-row title, and an optional trailing accessory (the kit
/// switcher). Lives here because one view now renders it for all three
/// catalogs (2026-07-25).

struct CatalogTabHeader<Accessory: View>: View {
    let title: String
    // The tab's create action; optional so title-only headers work.
    // Explicit `= nil` so the accessory-form memberwise init can omit these
    // (both catalog tabs moved creation into a list row, 2026-07-18).
    var addIdentifier: String? = nil
    /// Spoken VoiceOver name for the add key; falls back to "Add <title>".
    var addLabel: String? = nil
    var onAdd: (() -> Void)? = nil
    /// Optional expanding search (2026-07-18): the magnifier rides the
    /// top-right of the icon row and expands into a field that spans the
    /// row (the big title hides while searching), the same affordance the
    /// pushed catalogs use — one search UI everywhere.
    var search: HeaderSearchConfig? = nil
    @ViewBuilder var accessory: () -> Accessory

    @State private var searchExpanded = false
    /// At accessibility text sizes the heading can't share the icon row
    /// without shoving the trailing keys (search, +, kit switcher) off the
    /// edge, so it reflows to its own line below (#164 / axiom: reflow, don't
    /// cap the size).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var searching: Bool { search != nil && searchExpanded }
    private var titleOnRow: Bool { !searching && !dynamicTypeSize.isAccessibilitySize }
    private var titleBelowRow: Bool { !searching && dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Every root header wears the ++ key (Dave, build 44); it
                // toggles the shared reveal drawer.
                AppMenuKey()
                // The big title rides the icon row, left-aligned just right
                // of the ++ key (2026-07-19). `layoutPriority` (not
                // `fixedSize`) lets it claim its space first so all four tab
                // roots read at one full `.title` size, while the fixed
                // trailing keys stay reachable — any squeeze falls on the
                // variable-width kit switcher (its own `minimumScaleFactor`).
                if titleOnRow {
                    Text(title)
                        .font(.system(.title, weight: .bold))
                        .lineLimit(1)
                        .layoutPriority(1)
                        // +8 on top of the HStack's 8 pt spacing = a 16 pt gap
                        // from the ++ key, matching the key's own inset from
                        // the screen edge (Dave, 2026-07-19).
                        .padding(.leading, 8)
                }
                if let search {
                    // `HeaderSearchField` is a SINGLE stable instance; its
                    // Spacer/accessory/add key are conditionalized around it
                    // so it keeps identity (and its one-shot focus intent)
                    // across expand/collapse — see PushedHeader's note.
                    if !searchExpanded {
                        Spacer(minLength: 8)
                        accessory()
                        if let onAdd {
                            HeaderIconButton(systemImage: "plus", accessibilityLabel: addLabel ?? "Add \(title)", identifier: addIdentifier) {
                                onAdd()
                            }
                        }
                    }
                    HeaderSearchField(config: search, isExpanded: $searchExpanded)
                } else {
                    Spacer(minLength: 8)
                    accessory()
                    if let onAdd {
                        HeaderIconButton(systemImage: "plus", accessibilityLabel: addLabel ?? "Add \(title)", identifier: addIdentifier) {
                            onAdd()
                        }
                    }
                }
            }
            // At accessibility sizes the heading takes its own line below the
            // icon row, where it can wrap to full size instead of clipping.
            if titleBelowRow {
                Text(title)
                    .font(.system(.title, weight: .bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

/// discoverable before a second library exists).
struct LibrarySwitcherKey: View {
    let name: String
    /// Distinct per call site (the same switcher now rides four surfaces), so
    /// a future smoke test visiting more than one doesn't hit a multiple-match
    /// on a shared identifier (swift review).
    var identifier: String = "librarySwitcherButton"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(name)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    // A long kit name shrinks a touch, then TRUNCATES here
                    // rather than crowding the tab heading off the row (Dave,
                    // 2026-07-20). The heading claims its space first
                    // (`layoutPriority(1)` in CatalogTabHeader), so the
                    // switcher is what yields. NO hard `maxWidth` cap: that
                    // frame is greedy in this HStack (it competes with the
                    // Spacer) and would leave a gap before the chevron for
                    // short names like the default "main" (swift-reviewer catch).
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(.raisedKey())
        .accessibilityIdentifier(identifier)
    }
}
