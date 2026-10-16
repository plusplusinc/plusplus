import SwiftUI

/// A moment of a drag on a rail.
struct RailDragState<ID: Hashable> {
    var lifted: ID
    /// The slot the row was lifted from, where dropping it changes nothing.
    var origin: RailSlot<ID>
    /// Where the gap is open.
    var slot: RailSlot<ID>
    /// The card's top, in the rail's space.
    var cardTop: CGFloat
    /// How far below the row's top the finger holds it.
    var grab: CGFloat
}

extension View {
    /// A hold on this row lifts it, on iOS; a press in the rail column lifts nothing.
    @ViewBuilder
    func liftable(
        isEnabled: Bool,
        columnWidth: CGFloat,
        onPhase: @escaping (RailDrag.Phase, CGFloat) -> Void,
    ) -> some View {
        #if os(iOS)
        gesture(RailLiftGesture(
            isEnabled: isEnabled,
            columnWidth: columnWidth,
            onPhase: onPhase,
        ))
        #else
        self
        #endif
    }
}

/// A held row's card: raised off the screen, it bleeds past the row on both sides, with a grip
/// at its trailing edge. At rest, it is not drawn.
struct LiftedCard: View {
    let isLifted: Bool
    @ObserveHotReload private var hotReload

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.card)
            .fill(.pp(.surfaceRaised))
            .stroke(.pp(.borderStrong), lineWidth: 1)
            .overlay(alignment: .trailing) {
                Image(systemName: "line.2.horizontal")
                    .font(.ppButton)
                    .foregroundStyle(.pp(.textSecondary))
                    .padding(.trailing, Spacing.md)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, -Spacing.sm)
            .shadow(
                color: .pp(.shadow),
                radius: isLifted ? RailDrag.shadowRadius : 0,
                y: isLifted ? RailDrag.shadowY : 0,
            )
            .opacity(isLifted ? 1 : 0)
            .hotReloadable()
    }
}
