import CoreGraphics

/// Where a bar's key is, over the faces it can show, and what the bar draws for it: the key and
/// the floating button above it are one piece, placed from one depth (`KeyReach`). A face's `id`
/// is which key it is: a change of id swaps the key for another, the one showing going down out
/// of the screen's bottom edge with its words as they were, then the next coming up in from it,
/// one after the other, never two keys at once and never both words on one. A change within one
/// id, as "Log left" to "Log right", changes the words in place. Taken away, or ridden down out
/// of sight by the screen, the key goes with the words it had and is in no swap; back in sight,
/// it is the live key at once. The rise is not a stage: it is the animation from `leaving` to
/// `showing`, the live face drawn from where the key going ended, below the edge.
///
/// A swap starts and turns from levels, never from a change: wherever the bar follows its inputs,
/// a key showing as another kind starts leaving, and a key leaving whose drop is drawn all the way
/// down (`down`, the number of the swap drawn there) turns. Turned on the drop's end as a change,
/// with Pause landing in the frame the drop ended, the rest's keys once stayed below the edge
/// (2026-11-25): a next swap starting with the key still drawn down changed nothing to see.
struct KeyTray<Face: Equatable & Identifiable>: Equatable {
    /// What the screen gives the bar.
    struct Inputs: Equatable {
        var face: Face
        var isPresented: Bool
        /// Ridden down out of sight by the screen (`drop > 0`).
        var isDropped = false

        var inSight: Bool {
            isPresented && !isDropped
        }
    }

    enum Stage: Equatable {
        /// In the bar, as the face it last followed.
        case showing(Face)
        /// In a swap, going down with the words it had.
        case leaving(Face)
        /// Taken away or ridden down by the screen, drawn as the face it left with.
        case away(Face)

        var isLeaving: Bool {
            if case .leaving = self {
                true
            } else {
                false
            }
        }
    }

    /// What the bar draws: the face, whether the key is out in a swap, and where each part of
    /// its depth is headed, 0 or 1: the swap (`KeySwap`), which runs at a swap's own pace, the
    /// screen taking the key away (`KeyTravel`), run by the update's animation, and the screen's
    /// ride (`KeyRide`), which runs at its own pace.
    struct Drawn: Equatable {
        var face: Face
        var isOut: Bool
        var swap: SwapDrawn
        var away: CGFloat
        var ride: CGFloat
    }

    private(set) var stage: Stage
    /// The face as last followed, which a key rising, or back in sight, is drawn as.
    private(set) var live: Face
    /// How many swaps have started, so a swap's turn comes only for the swap it belongs to.
    private(set) var swaps = 0

    init(_ inputs: Inputs) {
        live = inputs.face
        stage = inputs.inSight ? .showing(inputs.face) : .away(inputs.face)
    }

    /// The face drawn: showing, the live face while it is the same key, so its words change in
    /// place; another key's, before the swap has started, the key as it was.
    var face: Face {
        switch stage {
        case let .showing(face), let .leaving(face), let .away(face): face
        }
    }

    /// Follows the screen's inputs and how far down the swap is drawn, as often as the bar is
    /// drawn: following the same again changes nothing. Out of sight, the key goes as it is
    /// drawn, leaving any swap; back in sight, it shows as the live face. Showing, the same kind
    /// takes the new words, and another kind starts the swap: the key showing goes down with its
    /// words. Leaving, once this swap's drop is drawn all the way down (`down`), it turns: the
    /// live face shows, rising from there, in the one change. Until then nothing changes: the key
    /// that comes in is the face live when it rises. A swap taken away, or since followed by
    /// another, has no turn.
    mutating func follow(_ inputs: Inputs, down: Int? = nil) {
        let drawn = face
        live = inputs.face
        guard inputs.inSight else {
            if case .away = stage {
                return
            }
            stage = .away(drawn.id == live.id ? live : drawn)
            return
        }
        switch stage {
        case .away:
            stage = .showing(live)
        case let .showing(face) where face.id == live.id:
            stage = .showing(live)
        case let .showing(face):
            stage = .leaving(face)
            swaps += 1
        case .leaving where down == swaps:
            stage = .showing(live)
        case .leaving:
            break
        }
    }

    /// What the bar draws for `inputs`, once followed.
    func drawn(for inputs: Inputs) -> Drawn {
        let pace: SwapDrawn.Pace = switch stage {
        case .leaving: .drop
        case .showing: .rise
        case .away: .update
        }
        return Drawn(
            face: face,
            isOut: isOut,
            swap: SwapDrawn(number: swaps, depth: stage.isLeaving ? 1 : 0, pace: pace),
            away: inputs.isPresented ? 0 : 1,
            ride: inputs.isDropped ? 1 : 0,
        )
    }

    /// Whether the key is going down out of sight in a swap; it takes no tap.
    var isOut: Bool {
        stage.isLeaving
    }
}

/// How far below its place a bar's key is drawn, and how far above its low place the floating
/// button is, from one depth: the button rides on the key, as one piece, its gap above the key's
/// top, until the key has gone further than the button's low place, where it stays.
/// Plain arithmetic, worked out off the main actor as the key's animation draws.
nonisolated struct KeyReach: Equatable {
    /// How far each move has the key down, 0 to 1, each run by the animation that changes it.
    struct Parts: Equatable {
        /// A swap: the key going down, then the next one rising from where it ended.
        var swap: CGFloat
        /// Taken away by the screen.
        var away: CGFloat
        /// Ridden down by the screen (`drop`).
        var drop: CGFloat
    }

    /// How far a swap takes the key down past its own height: to the screen's bottom edge, less
    /// how far below its place in the bar it is drawn.
    var swapBelow: CGFloat
    /// How far the screen runs on below the bar: a key taken away goes that far past its height.
    var bottomInset: CGFloat
    /// The floating button's bottom above the key's top.
    var gap: CGFloat

    /// How far below its place the key is drawn, a key `height` tall. With Reduce Motion a swap
    /// and a key taken away fade in place, so neither is drawn as travel. Ridden down by the
    /// screen, the key goes as far as one taken away, out of sight and no further, at the pace of
    /// a key going down (`KeyRide`): ridden a screen's height on the list's own curve, it was out
    /// of sight in three frames, much faster than any other key going down.
    func depth(_ parts: Parts, height: CGFloat, reduceMotion: Bool = false) -> CGFloat {
        let ride = parts.drop * (height + awayBelow)
        guard !reduceMotion else { return ride }
        return parts.swap * (height + swapBelow) + parts.away * (height + awayBelow) + ride
    }

    /// How far past its height a key taken away goes: on below the bar, and with no home
    /// indicator, at least as far as the floating button's gap, so the button riding on it comes
    /// down to its low place.
    private var awayBelow: CGFloat {
        max(bottomInset, gap)
    }

    /// How far above its low place, where its bottom is the key's at rest, the floating button
    /// is drawn: its gap above the key's top, down to the low place and no further. With Reduce
    /// Motion, at one place or the other, high while the key is to be in sight.
    func floatingLift(
        _ parts: Parts,
        height: CGFloat,
        reduceMotion: Bool = false,
        inSight: Bool = true,
    ) -> CGFloat {
        guard !reduceMotion else { return inSight ? height + gap : 0 }
        return max(height + gap - depth(parts, height: height), 0)
    }
}
