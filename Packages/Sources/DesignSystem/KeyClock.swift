import SwiftUI
import Synchronization

/// The time the bar's key runs its swap on: the frame's own, unless a hosted test steps a clock
/// of its own (`stepped`), so a frame there is one step, however slow the host. Sampled in real
/// time, a busy host drew a swap in 10 frames where its test landed something on frame 16, and
/// nothing landed (Xcode Cloud, 2026-11-26).
enum KeyClock {
    /// The clock a test steps, while it does; nil in the app.
    static var stepped: SteppedClock?

    /// `animation`, on the stepped clock while there is one.
    static func pace(_ animation: Animation) -> Animation {
        stepped.map { Animation(SteppedAnimation(base: animation, clock: $0)) } ?? animation
    }
}

/// Time that moves only when told to.
final nonisolated class SteppedClock: Sendable {
    private let time = Mutex<TimeInterval>(0)

    var now: TimeInterval {
        time.withLock { $0 }
    }

    func advance(by interval: TimeInterval) {
        time.withLock { $0 += interval }
    }
}

/// `base` run on `clock`'s time from the moment it was first asked, rather than the frame's.
/// It never merges with the animation before it, as a spring does: merged through the public
/// API, a spring took nothing from the one before and stood at its end at once. Unmerged, it
/// runs from where the one before is drawn, which at the swap's turn is at its end.
nonisolated struct SteppedAnimation: CustomAnimation {
    let base: Animation
    let clock: SteppedClock

    func animate<V: VectorArithmetic>(
        value: V,
        time _: TimeInterval,
        context: inout AnimationContext<V>,
    ) -> V? {
        let start = context.state[Start.self] ?? clock.now
        let value = base.animate(value: value, time: clock.now - start, context: &context)
        context.state[Start.self] = start
        return value
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.base == rhs.base && lhs.clock === rhs.clock
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(base)
        hasher.combine(ObjectIdentifier(clock))
    }

    private struct Start: AnimationStateKey {
        static var defaultValue: TimeInterval? {
            nil
        }
    }
}
