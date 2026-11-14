/// Where a bar's key is in a swap for another, over the faces it can show. A face's `id` is which
/// key it is: a change of id swaps the key for another, the one showing going down out of the
/// screen's bottom edge with its words as they were, then the next coming up in from it, one
/// after the other, never two keys at once and never both words on one. A change within one id,
/// as "Log left" to "Log right", changes the words in place. The rise is not a stage: it is the
/// animation from `arriving` to `showing`.
enum KeyStage<Face: Equatable & Identifiable>: Equatable {
    /// In the bar, as the face it last followed.
    case showing(Face)
    /// Going down with the words it had.
    case leaving(Face)
    /// The next key, placed below the edge with no animation, about to rise: the live face,
    /// which may still change while it is out of sight.
    case arriving
    /// Ridden down out of sight by the screen, as Start at a workout's start: in no swap, the
    /// live face, so whatever key it is now comes back up under the screen's own animation.
    case dropped

    /// What the bar draws, with `live` the face it is given now. Showing, the live face while it
    /// is the same key, so its words change in place at once; another key's face, given before
    /// the stage has followed it, draws the key as it was, so it leaves with its own words.
    func face(for live: Face) -> Face {
        switch self {
        case let .showing(face): face.id == live.id ? live : face
        case let .leaving(face): face
        case .arriving, .dropped: live
        }
    }

    /// Follows the screen riding the key down out of sight, or bringing it back up as `live`.
    /// Dropped, it leaves any swap it was in; back, it shows as the live face.
    mutating func drop(_ isDropped: Bool, live: Face) {
        if isDropped {
            self = .dropped
        } else if self == .dropped {
            self = .showing(live)
        }
    }

    /// Follows the live face changing to `new`: another key starts the one showing leaving with
    /// its words; the same key takes the new words. True when the key started leaving. Leaving
    /// or arriving, nothing changes: the key that comes in is the face live when it rises.
    mutating func follow(to new: Face) -> Bool {
        guard case let .showing(face) = self else { return false }
        guard face.id != new.id else {
            self = .showing(new)
            return false
        }
        self = .leaving(face)
        return true
    }

    /// The swap's timed beats: the key gone, the next placed below the edge; then it rises as
    /// `live`.
    mutating func advance(live: Face) {
        switch self {
        case .showing, .dropped:
            break
        case .leaving:
            self = .arriving
        case .arriving:
            self = .showing(live)
        }
    }

    /// Whether the key is down out of sight in a swap, leaving or about to rise.
    var isOut: Bool {
        switch self {
        case .showing, .dropped: false
        case .leaving, .arriving: true
        }
    }

    /// Whether the key takes taps: not in a swap.
    var takesTaps: Bool {
        !isOut
    }
}
