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
    /// Whether a move under way holds its shift until the pulse has landed, as down the rail, so
    /// the next exercise's parts come in later (`SetMotion.arriveDelay(_:waits:)`).
    @Entry public var shiftWaitsForPulse = false
}

/// One of the current exercise's parts coming in and going in turn (`View.part(_:)`).
private struct PartMotion: ViewModifier {
    let part: SetMotion.Part
    @Environment(\.shiftWaitsForPulse) private var shiftWaitsForPulse

    func body(content: Content) -> some View {
        content.transition(
            .asymmetric(
                insertion: .opacity.combined(with: .offset(y: SetMotion.arriveRise))
                    .animation(
                        .easeOut(duration: SetMotion.arriveFade)
                            .delay(SetMotion.arriveDelay(part, waits: shiftWaitsForPulse)),
                    ),
                removal: .opacity.combined(with: .offset(y: SetMotion.leaveDrop))
                    .animation(
                        .easeIn(duration: SetMotion.leaveFade)
                            .delay(SetMotion.leaveDelay(part)),
                    ),
            ),
        )
    }
}
