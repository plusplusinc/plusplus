import Foundation

/// What the big number on the set screen counts, for an effort that isn't
/// rep work.
///
/// A lifting set is a discrete thing you record after it happens: the
/// stage shows the numbers you are about to assert, and the screen waits.
/// A cardio effort is one continuous thing you WATCH while it happens, so
/// something has to be moving, and exactly one thing should be the hero.
///
/// The rule is a **fallback chain**, because no single answer is always
/// available. Distance-to-go is the best hero for a five-mile run and is
/// unavailable the moment GPS is denied, indoors, or on a rower; the
/// naive "always show distance remaining" rule would leave a blank hero
/// on most of the app's cardio. So:
///
/// 1. **Progress toward a target**, when that metric is measurable right
///    now. Duration always qualifies (the clock runs regardless), which
///    is why a targeted timed effort still counts down exactly as it did.
/// 2. **The best live measured value**, when there is nothing to close on.
/// 3. **Elapsed, counting up** — the terminus, because the clock always
///    runs and a hero that can be absent is not a hero.
///
/// ⚠️ The chain's existence is the point: before it, an untargeted cardio
/// effort had NO clock at all. Quick-starting a run put a distance card
/// reading "—" on screen with a Log key under it and nothing moving, and
/// an untargeted timed effort counted down from a hard-coded thirty
/// seconds and logged itself.
public enum CardioHero: Equatable, Sendable {
    /// Closing on a number: `metric` is measurable now and has a target.
    case progress(metric: WorkoutMetric, target: Double)
    /// A target nothing here can watch, on an exercise where nothing ever
    /// could — a 500 m erg piece, a 50-calorie bike sprint. The machine's
    /// console has the number and you have your eyes, so this is not a
    /// degradation and gets no apology: the stage shows the target and you
    /// log what the console said, exactly as it always did.
    case selfReported(metric: WorkoutMetric, target: Double)
    /// A live reading with nothing to close on (an open-ended run under
    /// GPS shows the distance climbing).
    case measured(WorkoutMetric)
    /// The clock, counting up from the moment the effort started.
    case elapsed

    /// Whether this hero is the clock — the two shapes the timer dock
    /// renders, as opposed to a number the stage owns.
    public var isClock: Bool {
        switch self {
        case .progress(let metric, _): metric == .duration
        case .selfReported: false
        case .measured(let metric): metric == .duration
        case .elapsed: true
        }
    }

    /// Whether the clock runs DOWN to a target rather than up from zero.
    public var countsDown: Bool {
        if case .progress(.duration, _) = self { return true }
        return false
    }
}

public extension CardioHero {
    /// What the hero resolved to, and what it had to give up to get there.
    struct Resolution: Equatable, Sendable {
        public let hero: CardioHero
        /// A target that exists but nothing can track live right now — the
        /// reason the hero degraded. The screen says so rather than
        /// silently showing a different number than the one you asked for
        /// (a denied GPS fix turning a five-mile run into a stopwatch is
        /// the case worth explaining).
        public let unmeasurableTarget: WorkoutMetric?

        public init(hero: CardioHero, unmeasurableTarget: WorkoutMetric? = nil) {
            self.hero = hero
            self.unmeasurableTarget = unmeasurableTarget
        }
    }

    /// Resolve the hero for one set.
    ///
    /// Returns nil for rep work, which is not a continuous effort and
    /// keeps the stage it has always had — that gate is what makes this
    /// invisible to every strength surface.
    ///
    /// `measurable` is what the device can read RIGHT NOW, not what the
    /// exercise tracks: `.duration` is always in it, `.distance` and
    /// `.pace` only while a location fix is live. Passing what is
    /// *tracked* instead would put distance-to-go on an erg.
    ///
    /// ⚠️ `profile.isOutdoor` is what separates "the device should be
    /// measuring this and isn't" from "nothing here ever measured it".
    /// A 500 m erg piece was always read off the console, so it keeps the
    /// stage it has always had and gets no apology; a five-mile run with
    /// GPS denied genuinely lost something, degrades to the clock, and
    /// says so.
    static func resolve(
        profile: MetricProfile,
        target: (WorkoutMetric) -> Double?,
        measurable: Set<WorkoutMetric>
    ) -> Resolution? {
        guard !profile.tracksReps else { return nil }

        let work = WorkoutMetric.workMetrics.filter(profile.contains)
        let targeted = work.filter { (target($0) ?? 0) > 0 }

        // 1. Close on a target we can actually watch. Driver priority
        //    order (reps > distance > calories > duration) decides which,
        //    so a distance-and-duration prescription counts down the
        //    distance while GPS holds and the duration when it doesn't.
        for metric in targeted where measurable.contains(metric) {
            if let value = target(metric) {
                return Resolution(hero: .progress(metric: metric, target: value))
            }
        }

        // 2. A target nothing can watch. On an INDOOR exercise that is
        //    simply how it has always worked — the console has the number
        //    — so the stage stays and nothing apologises. A prescribed
        //    4 × 500 m erg piece must not lose its distance card to a
        //    stopwatch.
        if let metric = targeted.first, let value = target(metric), !profile.isOutdoor {
            return Resolution(hero: .selfReported(metric: metric, target: value))
        }

        // Outdoors, a target that should have been measured and isn't is a
        // real loss, and the screen owes an explanation.
        let stranded = targeted.first { !measurable.contains($0) }

        // 3. The best live reading, preferring a real measurement over the
        //    clock — an open-ended run under GPS should show the distance
        //    climbing, not a stopwatch.
        for metric in work where metric != .duration && measurable.contains(metric) {
            return Resolution(hero: .measured(metric), unmeasurableTarget: stranded)
        }

        // 4. The clock. Always available, which is the whole reason the
        //    chain terminates here.
        return Resolution(hero: .elapsed, unmeasurableTarget: stranded)
    }
}
