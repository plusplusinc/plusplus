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
    /// The pill travels between segments rather than cutting (#216, the app's
    /// law for this control since the retired `SegmentedTabs`): selection
    /// slides, and a control that slides reads as one thing moving instead of
    /// two things blinking.
    @Namespace private var pill

    private var showsLabels: Bool { placement != .inline }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FindScope.allCases, id: \.self) { item in
                segment(item)
            }
        }
        .padding(.horizontal, 12)
        // Chrome that has to hold three labels on one row can't grow without
        // bound. The search field is NOT capped — its text is the user's own.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func segment(_ item: FindScope) -> some View {
        let selected = scope == item
        return Button {
            guard !selected else { return }
            withAnimation(Theme.Anim.selection) { scope = item }
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
            // Selected ink on a lit pill, unselected on bare glass — the same
            // pairing the tab bar's own selection uses, so the two controls
            // read as one grammar.
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            // The accessory row is short, so this is the whole of its height —
            // a 44 pt target would fight the bar's own sizing.
            .frame(minHeight: 34)
            .background {
                if selected {
                    // An OPAQUE fill, not `.thinMaterial` (Dave, 2026-07-26:
                    // the material pill was nearly invisible against the glass
                    // it sat on — a selection you have to look for isn't one).
                    Capsule()
                        .fill(Theme.surfaceRaised)
                        .matchedGeometryEffect(id: "scopePill", in: pill)
                }
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
