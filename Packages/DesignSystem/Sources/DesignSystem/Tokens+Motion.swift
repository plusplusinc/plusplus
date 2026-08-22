import SwiftUI

/// Motion tokens.
///
/// Durations are short on purpose: these are feedback, not decoration. A press that takes longer
/// than about a sixteenth of a second stops feeling like a physical key.
public enum Motion {
    /// A key sinking onto its plate, and springing back.
    public static let press: Animation = .easeOut(duration: 0.06)
    /// The default for state changes that should be noticed but not watched.
    public static let standard: Animation = .easeOut(duration: 0.15)
}
