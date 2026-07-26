import SwiftUI

/// The catalog scope picker, riding in the TabView's bottom accessory while
/// search is active.
///
/// The tab bar is the scope control the rest of the time (Routines · Exercises ·
/// Kit are tabs again as of 2026-07-26). But the search-role tab spends its
/// selection on search itself, so while you're searching there has to be
/// something else that says which catalog you're searching — this.
///
/// **It draws no background of its own** (Dave, 2026-07-26). A
/// `Picker(.segmented)` brings its own segmented backing, which inside the
/// accessory's glass capsule read as a box in a box. So this is plain segments
/// with a pill on the selected one, sitting directly on the glass the accessory
/// already provides — the same relationship the system's own tab platter draws
/// between its items and the bar beneath them.
///
/// **It follows the placement it is given.** `.expanded` (its own row above a
/// full tab bar) has room for icon AND label; `.inline` (beside a minimized bar)
/// does not, and three words there collide, so inline shows icons only. The
/// placement is the system's choice — `.tabBarMinimizeBehavior(.onScrollDown)`
/// is what moves between the two — and the app can only adapt.
struct ScopeSegmentedAccessory: View {
    @Binding var scope: FindScope

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    /// The pill TRAVELS between segments (#216, the app's law for this control
    /// since the retired `SegmentedTabs`): selection slides, and a control that
    /// slides reads as one thing moving rather than two things blinking.
    ///
    /// ⚠️ The direction of this matters and the first cut had it backwards. A
    /// conditional pill inside each segment, all sharing one id, is an INSERT
    /// and a REMOVE on every change — there is no single view whose frame can
    /// travel, so it cross-fades in place (Dave, build 138: "the background of
    /// that segmented picker doesn't animate its position"). Instead the
    /// segments publish invisible SOURCE frames and ONE pill follows whichever
    /// is selected: one view, one identity, a moving target.
    @Namespace private var pill

    private var showsLabels: Bool { placement != .inline }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FindScope.allCases, id: \.self) { item in
                segment(item)
            }
        }
        .background {
            Capsule()
                // A material rather than a flat fill (Dave, 2026-07-26), and
                // the THICKEST one: `.thinMaterial` and then an opaque
                // `Theme.surfaceRaised` both vanished into the glass beneath.
                // ⚠️ Materials are veils of the SYSTEM background, so in dark
                // mode thicker means darker — this reads as a capsule punched
                // into the glass, not one sitting on it. Contrast either way.
                .fill(.ultraThickMaterial)
                // Guarantees a defined edge whichever way the material
                // resolves against the glass in a given color scheme.
                .overlay(Capsule().strokeBorder(Theme.borderStrong))
                .matchedGeometryEffect(id: scope, in: pill, isSource: false)
        }
        // On the VALUE, not at the tap site. The accessory lives in a
        // system-owned container that can re-render outside our transaction, so
        // a `withAnimation` around the binding write is not something to lean
        // on — and this way the pill also travels when the scope changes from
        // somewhere other than a tap here.
        .animation(Theme.Anim.selection, value: scope)
        .padding(.horizontal, 12)
        // Chrome that has to hold three labels on one row can't grow without
        // bound. The search field is NOT capped — its text is the user's own.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func segment(_ item: FindScope) -> some View {
        let selected = scope == item
        return Button {
            scope = item
        } label: {
            HStack(spacing: 5) {
                Image(systemName: item.symbolName)
                    .font(.system(.footnote, weight: selected ? .semibold : .regular))
                if showsLabels {
                    Text(item.label)
                        .font(.system(.subheadline, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            // Selected ink on the pill, unselected on bare glass — the same
            // pairing the tab bar's own selection uses, so the two controls
            // read as one grammar.
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            // The accessory row is short, so this is the whole of its height —
            // a 44 pt target would fight the bar's own sizing.
            .frame(minHeight: 34)
            .background {
                // Publishes this segment's frame for the pill to travel to.
                // Draws nothing itself.
                Color.clear.matchedGeometryEffect(id: item, in: pill, isSource: true)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Inline drops the words on screen, never from VoiceOver.
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("scope-\(item.rawValue)")
    }
}
