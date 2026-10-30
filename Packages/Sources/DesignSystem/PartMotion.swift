import SwiftUI

extension View {
    /// One of the current exercise's parts under its name, coming in and going in turn
    /// (`SetMotion`): in, fading as it rises into place once the row has room; going, fading as
    /// it drops, bottom first, as the row starts to close.
    func part(_ part: SetMotion.Part) -> some View {
        modifier(PartMotion(part: part))
    }
}

extension EnvironmentValues {
    /// The way of a move to another exercise under way, whose shift holds until the pulse has
    /// landed, so the current exercise's parts go later (`SetMotion.leaveDelay(_:way:)`) and the
    /// next one's come in later (`SetMotion.arriveDelay(_:way:)`). None after the last set.
    @Entry public var exerciseMoveWay: SetMotion.Way?
    /// Counts the sets logged that stay on the current exercise: each one, the current node
    /// shrinks down and back, as its progress line rolls (Dave, 2026-10-30).
    @Entry public var currentBeat = 0
}

/// One of the current exercise's parts coming in and going in turn (`View.part(_:)`).
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
                    .animation(
                        .easeIn(duration: SetMotion.leaveFade)
                            .delay(SetMotion.leaveDelay(part, way: exerciseMoveWay)),
                    ),
            ),
        )
    }
}
