import SwiftUI

extension View {
    /// One of the current exercise's parts under its name, coming in and going in turn
    /// (`SetMotion`): in, fading as it rises into place once the row has room; going, fading as
    /// it drops, bottom first, as the row starts to close.
    func part(_ part: SetMotion.Part) -> some View {
        modifier(PartMotion(part: part))
    }

    /// Room above, animated as layout: a plain `.padding(.top:)` changed in a move drew the
    /// views inserted in it at their end places, 24 pt off, for the move's length.
    public func topSpace(_ space: CGFloat) -> some View {
        modifier(TopSpace(space: space))
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

/// One of the current exercise's parts coming in and going in turn (`View.part(_:)`): going,
/// faded before the row's bottom reaches it, never cut off by it or drawn over what is below.
private struct PartMotion: ViewModifier {
    let part: SetMotion.Part
    @Environment(\.exerciseMoveWay) private var exerciseMoveWay

    func body(content: Content) -> some View {
        content.transition(
            .asymmetric(
                insertion: .opacity.combined(with: .offset(y: SetMotion.arriveRise))
                    .animation(
                        .easeOut(duration: SetMotion.arriveFade)
                            .delay(SetMotion.arriveDelay(part, way: exerciseMoveWay)),
                    ),
                removal: .opacity.combined(with: .offset(y: SetMotion.leaveDrop))
                    .animation(SetMotion.leaving(part, way: exerciseMoveWay)),
            ),
        )
    }
}
