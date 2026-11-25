import CoreGraphics

/// Where a bar's key is, over the faces it can show, and what the bar draws for it: the key and
/// the floating button above it are one piece, placed from one depth (`KeyReach`). A face's `id`
/// is which key it is: a change of id swaps the key for another, the one showing going down out
/// of the screen's bottom edge with its words as they were, then the next coming up in from it,
/// one after the other, never two keys at once and never both words on one. A change within one
/// id, as "Log left" to "Log right", changes the words in place. Taken away, or ridden down out
/// of sight by the screen, the key goes with the words it had and is in no swap; back in sight,
/// it is the live key at once. The rise is not a stage: it is the animation from `arriving` to
/// `showing`.
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
        /// In a swap, below the edge, the live face, about to rise.
        case arriving
        /// Taken away or ridden down by the screen, drawn as the face it left with.
        case away(Face)
    }

    /// What the bar draws: the face, whether the key is out in a swap, and where each part of
    /// its depth is headed, 0 or 1, for the animation of the update that drew it to run to.
    struct Drawn: Equatable {
        var face: Face
        var isOut: Bool
        var targets: KeyReach.Parts
    }

    private(set) var stage: Stage
    /// The face as last followed, which a key rising, or back in sight, is drawn as.
    private(set) var live: Face

    init(_ inputs: Inputs) {
        live = inputs.face
        stage = inputs.inSight ? .showing(inputs.face) : .away(inputs.face)
    }

    /// The face drawn: showing, the live face while it is the same key, so its words change in
    /// place; another key's, before the swap has started, the key as it was.
    var face: Face {
        switch stage {
        case let .showing(face): face.id == live.id ? live : face
        case let .leaving(face), let .away(face): face
        case .arriving: live
        }
    }

    /// Follows the screen's inputs, as often as the bar is drawn: following the same inputs
    /// again changes nothing. Out of sight, the key goes as it is drawn, leaving any swap; back
    /// in sight, it shows as the live face. Showing, the same kind takes the new words, and
    /// another kind waits for the swap to start (`needsSwap`). In a swap, nothing changes: the
    /// key that comes in is the face live when it rises.
    mutating func follow(_ inputs: Inputs) {
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
        case .showing, .leaving, .arriving:
            break
        }
    }

    /// What the bar draws for `inputs`, once followed.
    func drawn(for inputs: Inputs) -> Drawn {
        Drawn(
            face: face,
            isOut: isOut,
            targets: KeyReach.Parts(
                swap: isOut ? 1 : 0,
                away: inputs.isPresented ? 0 : 1,
                drop: inputs.isDropped ? 1 : 0,
            ),
        )
    }

    /// Showing as one kind while another is live: the swap is to start.
    var needsSwap: Bool {
        guard case let .showing(face) = stage else { return false }
        return face.id != live.id
    }

    /// The swap's start: the key showing goes down with its words.
    mutating func startLeaving() {
        guard needsSwap, case let .showing(face) = stage else { return }
        stage = .leaving(face)
    }

    /// The swap's timed beats: the key gone, the next placed below the edge; then it rises as
    /// the live face. Out of a swap, nothing.
    mutating func advance() {
        switch stage {
        case .leaving: stage = .arriving
        case .arriving: stage = .showing(live)
        case .showing, .away: break
        }
    }

    /// Whether the key is down out of sight in a swap, leaving or about to rise; it takes no tap.
    var isOut: Bool {
        switch stage {
        case .leaving, .arriving: true
        case .showing, .away: false
        }
    }
}

/// How far below its place a bar's key is drawn, and how far above its low place the floating
/// button is, from one depth: the button rides on the key, as one piece, its gap above the key's
/// top, until the key has gone further than the button's low place, where it stays.
struct KeyReach: Equatable {
    /// How far each move has the key down, 0 to 1, each run by the animation that changes it.
    struct Parts: Equatable {
        /// The bar's own swap.
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
    /// How far the screen rides the key down: at least off the screen.
    var drop: CGFloat
    /// The floating button's bottom above the key's top.
    var gap: CGFloat

    /// How far below its place the key is drawn, a key `height` tall. With Reduce Motion a swap
    /// and a key taken away fade in place, so neither is drawn as travel.
    func depth(_ parts: Parts, height: CGFloat, reduceMotion: Bool = false) -> CGFloat {
        let ride = parts.drop * max(drop, height + bottomInset + Spacing.sm)
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
