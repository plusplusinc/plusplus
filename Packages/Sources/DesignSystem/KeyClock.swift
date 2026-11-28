import SwiftUI

/// Where the bar's key takes the animations of its swap: a seam a hosted test sets to run them
/// on a clock it steps, so a frame there is one step however slow the host. Sampled in real
/// time, a busy host drew a swap in 10 frames where its test landed something on frame 16, and
/// nothing landed (Xcode Cloud, 2026-11-26).
enum KeyClock {
    /// Nil in the app, so the key's animations pass through unchanged. Only a hosted test sets
    /// it, for its own run: one global is safe because `DesignSystemTests` runs one test at a
    /// time (its test plan's `parallelizable: false`).
    static var paced: ((Animation) -> Animation)?

    /// `animation`, as a test paces it while one does.
    static func pace(_ animation: Animation) -> Animation {
        paced?(animation) ?? animation
    }
}
