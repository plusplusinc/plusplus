/// Where a bar's key is in a swap for another, over the faces it can show. A face's `id` is which
/// key it is: a change of id swaps the key for another, the one showing going down out of the
/// screen's bottom edge with its words as they were, then the next coming up in from it, one
/// after the other, never two keys at once and never both words on one. A change within one id,
/// as "Log left" to "Log right", changes the words in place.
///
/// The rise is not a stage: it is the animation from `arriving` to `showing`.
enum KeyStage<Face: Equatable & Identifiable>: Equatable {
    /// In the bar; its words follow the live face.
    case showing(Face)
    /// Going down with the words it had; `next` is the live face, which comes in once it has gone.
    case leaving(Face, next: Face)
    /// The next key, placed below the edge with no animation, about to rise.
    case arriving(Face)

    /// What the bar draws, with `live` the face it is given now. Showing or arriving, the live
    /// words while they are the same key's, so they change in the same update that changed them;
    /// another key's, the face it had, until the swap has started. Leaving, the face going.
    func face(for live: Face) -> Face {
        switch self {
        case let .showing(face), let .arriving(face):
            live.id == face.id ? live : face
        case let .leaving(face, _):
            face
        }
    }

    /// Follows `live`, the face the bar is given: another key starts the one showing leaving.
    /// While leaving, only what comes next follows. Not presented, the stage is the live face at
    /// once, so a key that comes back is already the new one, with no swap.
    mutating func follow(_ live: Face, isPresented: Bool) {
        guard isPresented else {
            self = .showing(live)
            return
        }
        switch self {
        case let .showing(face):
            self = face.id == live.id ? .showing(live) : .leaving(face, next: live)
        case let .leaving(face, _):
            self = .leaving(face, next: live)
        case .arriving:
            self = .arriving(live)
        }
    }

    /// The swap's timed beats: the key gone, the next placed below the edge; then it rises.
    mutating func advance() {
        switch self {
        case .showing:
            break
        case let .leaving(_, next):
            self = .arriving(next)
        case let .arriving(face):
            self = .showing(face)
        }
    }

    /// Whether the key is down out of sight, leaving or about to rise.
    var isOut: Bool {
        if case .showing = self {
            false
        } else {
            true
        }
    }

    /// Whether the key takes taps: only while showing.
    var takesTaps: Bool {
        !isOut
    }
}
