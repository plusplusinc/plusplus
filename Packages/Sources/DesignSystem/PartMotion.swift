import SwiftUI

extension View {
    /// One of the current exercise's parts under its name, coming in as the row opens
    /// (`SetMotion`): the progress line fading in where the detail line has gone, the figures and
    /// the equipment drawn whole from the start, shown as the row's opening bottom reaches them.
    /// Going, each is gone at once from the column, its place taken by the closing row's copy
    /// (`ClosingParts`), which rides up with the name until the closing bottom has cut it off.
    func part(_ part: SetMotion.Part) -> some View {
        modifier(PartMotion(part: part))
    }

    /// A row's bars at its detail line's end, coming in and going as the progress line does on
    /// the current exercise, which takes their place.
    func rowBars() -> some View {
        modifier(RowBarsMotion())
    }

    /// Room above, laid out afresh on every frame as it animates, so what a row grows or keeps
    /// as it closes moves with the row: a plain padding's change moved the row's views from where
    /// they were, but drew those coming in at their end places, a closing row's parts 24 pt above
    /// its name's second line for the move's first half second (2026-11-19).
    public func topSpace(_ space: CGFloat) -> some View {
        modifier(TopSpace(space: space))
    }

    /// The move under way that the parts in here go and come in on: its way, or none.
    public func exerciseMove(_ way: SetMotion.Way?) -> some View {
        environment(\.exerciseMoveWay, way)
    }
}

extension EnvironmentValues {
    /// The way of a move to another exercise under way, whose shift holds until the pulse has
    /// landed, so the current exercise's parts go later (`SetMotion.leaveDelay(_:way:)`) and the
    /// next one's come in later (`SetMotion.arriveDelay(_:way:)`). None after the last set.
    @Entry public var exerciseMoveWay: SetMotion.Way?
}

/// Room above (`View.topSpace(_:)`).
private struct TopSpace: ViewModifier, Animatable {
    var space: CGFloat

    nonisolated var animatableData: CGFloat {
        get { space }
        set { space = newValue }
    }

    func body(content: Content) -> some View {
        content.padding(.top, space)
    }
}

/// One of the current exercise's parts coming in (`View.part(_:)`). Faded in after delays fixed
/// in time, the figures and equipment left the row tall and empty under its name for a third of
/// a second at Start (2026-11-19); drawn from the start, the row's bottom shows them as it opens.
private struct PartMotion: ViewModifier {
    let part: SetMotion.Part
    @Environment(\.exerciseMoveWay) private var exerciseMoveWay

    func body(content: Content) -> some View {
        let insertion: AnyTransition = switch part {
        // In the detail line's place, once it has gone, never over it.
        case .progress: .opacity.animation(SetMotion.progressIn(way: exerciseMoveWay))
        // Opening from its top as the row does, so the equipment under it, shown on the next
        // exercise through a rest, moves down with its room's edge: drawn whole at once, the
        // figures lay over the equipment as it went down past them.
        case .figures: .modifier(active: Opening(open: 0), identity: Opening(open: 1))
        case .equipment: .identity
        }
        return content.transition(.asymmetric(insertion: insertion, removal: .identity))
    }
}

/// A part `open` of its height tall, drawn from its top and cut off at that height.
private struct Opening: ViewModifier, Animatable {
    var open: CGFloat

    nonisolated var animatableData: CGFloat {
        get { open }
        set { open = newValue }
    }

    func body(content: Content) -> some View {
        OpeningLayout(open: open) { content }
            .clipped()
    }
}

/// Its one subview from the top, `open` of its own height tall.
private struct OpeningLayout: Layout {
    let open: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let offer = ProposedViewSize(width: proposal.width, height: nil)
        let size = subviews.first?.sizeThatFits(offer) ?? .zero
        return CGSize(width: proposal.width ?? size.width, height: size.height * open)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        subviews.first?.place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: nil),
        )
    }
}

/// A row's bars coming in and going (`View.rowBars()`).
private struct RowBarsMotion: ViewModifier {
    @Environment(\.exerciseMoveWay) private var exerciseMoveWay

    func body(content: Content) -> some View {
        content.transition(
            .asymmetric(
                insertion: .opacity.combined(with: .offset(y: SetMotion.arriveRise))
                    .animation(
                        .easeOut(duration: SetMotion.arriveFade)
                            .delay(SetMotion.arriveDelay(.progress, way: exerciseMoveWay)),
                    ),
                removal: .opacity.combined(with: .offset(y: SetMotion.leaveDrop))
                    .animation(
                        .easeIn(duration: SetMotion.leaveFade)
                            .delay(SetMotion.leaveDelay(.progress, way: exerciseMoveWay)),
                    ),
            ),
        )
    }
}

/// The parts a closing row shows under its name until its bottom has cut them off: drawn while
/// `growth`, animated with the row's height, is above 0 on a row that is no longer the current
/// exercise. Laid over the row's lines, not in its column, so the row's height at rest is
/// measured without them, and they ride up with the name as it shrinks. Taken out of the column at
/// once, the figures stood where they were as the name shrank, a gap opening over them, and
/// were cut off from below over about eight frames (2026-11-19).
struct ClosingParts<Parts: View>: View, Animatable {
    var growth: CGFloat
    let isClosing: Bool
    @ViewBuilder let parts: Parts

    nonisolated var animatableData: CGFloat {
        get { growth }
        set { growth = newValue }
    }

    var body: some View {
        // Shown and gone at once: on the move's delayed curve, the default fade held them unseen
        // until the shift.
        if isClosing, growth > 0 {
            parts.transition(.identity)
        }
    }
}

/// The closing row's progress line going on `animation` as it appears, as the detail line comes
/// back in its place, its room giving way to the detail line's, so the parts under it move up
/// with it: kept, the row stood open two lines under the detail line as it closed.
struct ProgressGoing<Room: View, Line: View>: View {
    let animation: Animation
    /// The detail line's room, unseen.
    @ViewBuilder let room: Room
    @ViewBuilder let line: Line
    @State private var isGone = false

    var body: some View {
        GoingRoom(gone: isGone ? 1 : 0) {
            room
            line.opacity(isGone ? 0 : 1)
        }
        .onAppear {
            withAnimation(animation) { isGone = true }
        }
    }
}

/// Its second subview over its first, from the top, as tall as the taller while `gone` is 0 and
/// the first once it is 1.
private struct GoingRoom: Layout, Animatable {
    var gone: CGFloat

    nonisolated var animatableData: CGFloat {
        get { gone }
        set { gone = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let offer = ProposedViewSize(width: proposal.width, height: nil)
        let room = subviews[0].sizeThatFits(offer), line = subviews[1].sizeThatFits(offer)
        // From the two's room as the current exercise laid them out over each other.
        let start = max(room.height, line.height)
        return CGSize(
            width: max(room.width, line.width),
            height: start + (room.height - start) * gone,
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let offer = ProposedViewSize(width: proposal.width, height: nil)
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: offer)
        }
    }
}
