// How long a new row rests, by what kind of work it is, so every built-in starts somewhere a
// lifter would put it and a new exercise needs no number of its own.

extension Exercise {
    /// The rest between sets a new row starts with, in seconds, the first rule that fits: none
    /// for a stretch, 60 s for conditioning, 30 s for a hold, an anti-rotation, or balance work,
    /// 90 s for a single-joint lift or one with no movement pattern, 3 min for a barbell
    /// compound, and 2 min for any other compound.
    var defaultRest: Int {
        switch tags.kind {
        case .stretch: return 0
        case .conditioning: return 60
        case .balance: return 30
        case .strength: break
        }
        switch tags.movement {
        case .hold, .rotation: return 30
        case nil: return 90
        case _ where tags.singleJoint: return 90
        case _ where load == .bar: return 180
        default: return 120
        }
    }
}
