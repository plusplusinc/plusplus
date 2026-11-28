import SwiftUI

/// A view going as its room closes over it, for content under it that rises into the room on
/// the same animation: it is cut off from the bottom up, at the edge that content has risen
/// to, as it fades, so the rising content never shows through it. Faded alone, the calendar
/// under an earlier Apple Health card on Log rose through the card's words. Coming in, it
/// runs backward: uncovered from the top down as its room opens.
public struct CutAway: Transition {
    public init() { }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .mask(alignment: .top) {
                Rectangle()
                    .scaleEffect(x: 1, y: phase.isIdentity ? 1 : 0, anchor: .top)
            }
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

extension Transition where Self == CutAway {
    /// `.transition(.cutAway)`.
    public static var cutAway: CutAway {
        CutAway()
    }
}

extension Animation {
    /// A card, or a row on one, coming or going with Reduce Motion, in place of its `.snappy`
    /// move: a crossfade, as Void's row in Settings and Log's Apple Health card do.
    public static let cardCrossfade = Animation.easeInOut(duration: cardCrossfadeDuration)

    /// A card's room closing with Reduce Motion, for a card that leaves for good: what it moves
    /// holds still while the card fades on `cardCrossfade` (give the card's transition that
    /// animation), then is where it goes in one step, so nothing slides and nothing shows
    /// through the card. Its own end, not a timer, so the step lands with the fade's.
    public static let afterCardCrossfade = Animation(HoldThenStep(duration: cardCrossfadeDuration))

    private static let cardCrossfadeDuration = 0.2
}

extension AnyTransition {
    /// A fade on `Animation.cardCrossfade`, a card's or its row's going with Reduce Motion.
    public static var cardCrossfade: AnyTransition {
        .opacity.animation(.cardCrossfade)
    }
}

/// No change for `duration`, then the whole change at once.
private struct HoldThenStep: CustomAnimation {
    let duration: TimeInterval

    func animate<V: VectorArithmetic>(
        value _: V,
        time: TimeInterval,
        context _: inout AnimationContext<V>,
    ) -> V? {
        time < duration ? .zero : nil
    }
}
