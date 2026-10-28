import Foundation

/// Every timing in logging a set, in one place, so a tweak tried on the phone is one line.
public enum SetMotion {
    /// How far along the track the key has to go to log the set: past it, the arrow turns to a
    /// check with a haptic, and a release logs; slid back under it, the arrow comes back.
    static let commit = 2.0 / 3
    /// A key let go short of `commit` springing back to the start.
    static let springBack = 0.35
    /// A key let go past `commit` finishing its slide to the track's end.
    static let finish = 0.18
    /// The key resting at the end while the progress line rolls to the next set.
    static let rest = 0.8
    /// The key fading out at the end, then in again at the start.
    static let fadeOut = 0.15
    static let fadeIn = 0.2
    /// "Set 2 of 3" rolling up and out as "Set 3 of 3" rolls up and in, once the set logs.
    public static let roll = 0.3
    /// How far the progress line rolls, as a share of its height.
    public static let rollShare = 1.0
}
