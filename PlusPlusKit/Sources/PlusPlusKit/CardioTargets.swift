import Foundation

/// The two-of-three law for a cardio prescription.
///
/// Distance, duration and pace are not three independent numbers — any
/// two fix the third. The planning sheet used to offer all three as equal
/// steppers, which let you author a contradiction ("2 mi, 10:00, 6:00/mi")
/// and left the execution driver to be decided silently behind your back.
///
/// The rule: **at most two of the three are ever STORED; the third is
/// computed for display and never written.**
///
/// ⚠️ That last clause is load-bearing, not tidiness. `MetricProfile.driver`
/// picks the highest-priority work metric *that has a target*, and distance
/// outranks duration. If a derived distance were stored, "30 minutes at
/// 9:00/mi" would silently become a 3.33-mile distance-driven set — the
/// user asked for a half-hour and got an odometer. Keeping derived values
/// out of storage means the settled driver rule needs no exception at all,
/// and derivation needs no new column either: which metric is derived
/// falls out of which of the three are nil.
public enum CardioTargets {
    /// The three interdependent metrics, in the order they read.
    public static let triad: [WorkoutMetric] = [.distance, .duration, .pace]

    /// Whether the law applies at all. A profile tracking one of the three
    /// (a plank's bare duration) has nothing to derive from, so every sheet
    /// that isn't cardio renders exactly as it did before.
    public static func applies(to profile: MetricProfile) -> Bool {
        triad.filter(profile.contains).count >= 2
    }

    /// The metric currently rendering as derived, given which of the triad
    /// carry stored values. nil when fewer than two are stored (nothing to
    /// compute from), when all three somehow are (a store written before
    /// this law — the sheet shows them all as entered and the next edit
    /// evicts one), or when the profile doesn't track the third.
    public static func derivedMetric(
        profile: MetricProfile,
        stored: (WorkoutMetric) -> Double?
    ) -> WorkoutMetric? {
        let tracked = triad.filter(profile.contains)
        guard tracked.count >= 2 else { return nil }
        let missing = tracked.filter { stored($0) == nil }
        guard missing.count == 1 else { return nil }
        return missing[0]
    }

    /// The computed value for `metric`, from the other two. nil when the
    /// inputs are missing, non-finite, or zero in a place that would
    /// divide — a prescription is never worth an infinity.
    ///
    /// `distance` is in the profile's own unit; `duration` and `pace` are
    /// plain seconds, pace against its reference (per 100 m, 500 m, 100 yd,
    /// km or mile). The conversion goes through meters because that is the
    /// only denomination a pace reference is expressed in.
    ///
    /// ⚠️ Pass the PROFILE's reference wherever you have one. The unit's own
    /// convention is only a fallback, and it is wrong for exactly the case
    /// `PaceReference` exists for: a metric pool is denominated in meters
    /// and splits per 100, where the unit alone would say per 500.
    public static func derive(
        _ metric: WorkoutMetric,
        distance: Double?,
        durationSeconds: Double?,
        paceSeconds: Double?,
        unit: DistanceUnit,
        paceReference: PaceReference? = nil
    ) -> Double? {
        let reference = (paceReference ?? unit.defaultPaceReference).meters
        guard reference > 0 else { return nil }

        switch metric {
        case .duration:
            guard let distance, let paceSeconds,
                  distance > 0, paceSeconds > 0 else { return nil }
            return finite(unit.meters(from: distance) / reference * paceSeconds)

        case .distance:
            guard let durationSeconds, let paceSeconds,
                  durationSeconds > 0, paceSeconds > 0 else { return nil }
            let meters = durationSeconds / paceSeconds * reference
            return finite(unit.value(fromMeters: meters))

        case .pace:
            guard let distance, let durationSeconds,
                  distance > 0, durationSeconds > 0 else { return nil }
            let references = unit.meters(from: distance) / reference
            guard references > 0 else { return nil }
            return finite(durationSeconds / references)

        default:
            return nil
        }
    }

    /// Which stored metric has to make room when the user fills the last
    /// empty slot. nil when there is room already, or when `entering` is
    /// itself already stored (that's an edit, not an addition).
    ///
    /// **Evict pace if it is stored, else evict duration.** One rule, and
    /// it does the right thing every time: it always keeps the value the
    /// user just touched, and it prefers to keep a metric that ENDS the
    /// effort (distance, duration) over one that merely describes its rate.
    /// So dialing pace onto a distance-and-duration prescription drops the
    /// duration and derives it back, which is what "5 miles at 9:00" means.
    ///
    /// ⚠️ **One slot always stays empty**, whether the profile tracks all
    /// three or only two. On a three-member profile that empty slot is the
    /// derived reading. On a TWO-member one (a spin bike's distance and
    /// duration, with no pace to relate them) nothing can be computed, so
    /// the empty slot is simply the half of the prescription you didn't
    /// state — and that matters more, not less: with no pace there is no
    /// sense in which "45 minutes" and "20 km" are the same instruction,
    /// and `driver` would silently pick distance. Stating one clears the
    /// other rather than leaving a contradiction for execution to settle.
    public static func evicted(
        entering metric: WorkoutMetric,
        profile: MetricProfile,
        stored: (WorkoutMetric) -> Double?
    ) -> WorkoutMetric? {
        guard triad.contains(metric), profile.contains(metric), stored(metric) == nil else { return nil }
        let tracked = triad.filter(profile.contains)
        let others = tracked.filter { $0 != metric && stored($0) != nil }
        guard others.count >= max(1, tracked.count - 1) else { return nil }
        // Pace first, then duration, then distance. The last rung only
        // comes up on a two-member profile, where the entered metric is
        // itself the duration and distance is all that is left to drop.
        return [.pace, .duration, .distance].first(where: others.contains)
    }

    /// How long this effort actually takes, for the routine estimate: the
    /// stored duration when there is one, else the duration derived from a
    /// distance and a pace. nil when the prescription says neither — an
    /// open-ended run has no honest estimate, and inventing one is how a
    /// five-mile run came to read "45 seconds".
    public static func estimatedSeconds(
        profile: MetricProfile,
        stored: (WorkoutMetric) -> Double?
    ) -> Int? {
        // ⚠️ The profile gate is load-bearing: `RoutineExercise.target`
        // returns the raw durationSeconds column whatever the profile
        // tracks, so a hand-authored program file with a stray
        // `durationSeconds` on a bench-press entry would otherwise charge
        // that instead of the per-set estimate.
        if profile.contains(.duration), let duration = stored(.duration), duration > 0 {
            return Int(duration.rounded())
        }
        guard profile.contains(.distance), profile.contains(.pace) else { return nil }
        guard let seconds = derive(
            .duration,
            distance: stored(.distance),
            durationSeconds: nil,
            paceSeconds: stored(.pace),
            unit: profile.distanceUnit,
            paceReference: profile.paceReference
        ) else { return nil }
        return Int(seconds.rounded())
    }

    private static func finite(_ value: Double) -> Double? {
        value.isFinite && value > 0 ? value : nil
    }
}
