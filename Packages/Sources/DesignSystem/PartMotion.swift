import SwiftUI

extension View {
    /// One of the current exercise's parts under its name, coming in and going in turn
    /// (`SetMotion`): in, fading as it rises into place once the row has room; going, fading as
    /// it drops, bottom first, as the row starts to close.
    func part(_ part: SetMotion.Part) -> some View {
        modifier(PartMotion(part: part))
    }

    /// The move under way that the parts in here go and come in on: its way, or none, and
    /// whether the parts under the caption line leave under the row's closing bottom.
    public func exerciseMove(_ way: SetMotion.Way?, leavesUnderCut: Bool) -> some View {
        environment(\.exerciseMoveWay, way).environment(\.partsLeaveUnderCut, leavesUnderCut)
    }
}

extension EnvironmentValues {
    /// The way of a move to another exercise under way, whose shift holds until the pulse has
    /// landed, so the current exercise's parts go later (`SetMotion.leaveDelay(_:way:)`) and the
    /// next one's come in later (`SetMotion.arriveDelay(_:way:)`). None after the last set.
    @Entry public var exerciseMoveWay: SetMotion.Way?
    /// Whether the figures and the equipment go under the row's bottom, closing from the tap,
    /// dimming as it cuts them off, as into a superset round's rest above: faded at once, they
    /// left the row standing empty and tall under its name as it closed.
    @Entry var partsLeaveUnderCut = false
}

/// One of the current exercise's parts coming in and going in turn (`View.part(_:)`).
private struct PartMotion: ViewModifier {
    let part: SetMotion.Part
    @Environment(\.exerciseMoveWay) private var exerciseMoveWay
    @Environment(\.partsLeaveUnderCut) private var leavesUnderCut

    func body(content: Content) -> some View {
        // Under the cut they dim over the whole close as its bottom passes them. The progress
        // line still goes at once, before the detail line comes back in its place.
        let leaving = leavesUnderCut && part != .progress
            ? Animation.easeIn(duration: SetMotion.restAboveOpen)
            : .easeIn(duration: SetMotion.leaveFade)
            .delay(SetMotion.leaveDelay(part, way: exerciseMoveWay))
        let arriveDelay = SetMotion.arriveDelay(part, way: exerciseMoveWay)
        return content.transition(
            .asymmetric(
                insertion: .opacity.combined(with: .offset(y: SetMotion.arriveRise))
                    .animation(.easeOut(duration: SetMotion.arriveFade).delay(arriveDelay)),
                removal: .opacity
                    .combined(with: .offset(y: leavesUnderCut ? 0 : SetMotion.leaveDrop))
                    .animation(leaving),
            ),
        )
    }
}
