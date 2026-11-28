// Runs only where UIKit exists, as the hosted tests that use it do.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Synchronization

/// A clock a hosted test advances itself, so an animation on it draws the same frames on a busy
/// host as on an idle one. Sendable, and locked, because SwiftUI may ask an animation for its
/// value off the main thread.
final nonisolated class SteppedClock: Sendable {
    private let time = Mutex<TimeInterval>(0)

    var now: TimeInterval {
        time.withLock { $0 }
    }

    func advance(by interval: TimeInterval) {
        time.withLock { $0 += interval }
    }

    /// `animation` run on this clock, for `KeyClock.paced`.
    func pace(_ animation: Animation) -> Animation {
        Animation(SteppedAnimation(base: animation, clock: self))
    }
}

/// `base` run on `clock`'s time, from the moment it was first asked, rather than the frame's.
/// It merges as `base` does, so a rise's spring takes over a drop in flight as in the app.
nonisolated struct SteppedAnimation: CustomAnimation {
    let base: Animation
    let clock: SteppedClock

    func animate<V: VectorArithmetic>(
        value: V,
        time _: TimeInterval,
        context: inout AnimationContext<V>,
    ) -> V? {
        let start = context.state[Start.self] ?? clock.now
        context.state[Start.self] = start
        return base.animate(value: value, time: clock.now - start, context: &context)
    }

    /// Taking over one of these, it merges as `base` would, on the previous one's stepped time,
    /// whose start the state handed over holds. Taking over several running together, SwiftUI
    /// hands over a combining animation's state, which holds no start, and gives only real time
    /// since the first of them began: a spring merged on it drew different frames on a busy
    /// host, so there it runs alongside them instead, as a timing curve does.
    func shouldMerge<V: VectorArithmetic>(
        previous: Animation,
        value: V,
        time _: TimeInterval,
        context: inout AnimationContext<V>,
    ) -> Bool {
        guard let start = context.state[Start.self] else { return false }
        return base.shouldMerge(
            previous: previous,
            value: value,
            time: clock.now - start,
            context: &context,
        )
    }

    func velocity<V: VectorArithmetic>(
        value: V,
        time _: TimeInterval,
        context: AnimationContext<V>,
    ) -> V? {
        let start = context.state[Start.self] ?? clock.now
        return base.velocity(value: value, time: clock.now - start, context: context)
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

#endif
