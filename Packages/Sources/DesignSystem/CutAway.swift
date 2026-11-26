import SwiftUI

/// A view going as its room closes over it, for content under it that rises into the room on
/// the same animation: it is cut off from the bottom up, at the edge that content has risen
/// to, as it fades, so the rising content never shows through it. Faded alone, the calendar
/// under Log's Apple Health card (`OfferCard`) rose through the card's words. Coming in, it
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
    public static let cardCrossfade = Animation.easeInOut(duration: 0.2)
}
