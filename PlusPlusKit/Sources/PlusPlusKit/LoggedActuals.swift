import Foundation

/// What a device may honestly record as an ACTUAL.
///
/// The wrist used to answer this question by copying the plan: logging a
/// step wrote `step.targetWeight` / `targetRepsLower` / `targetDuration`
/// into the result and mirrored `extras: step.extraTargets`, verbatim. Row
/// 400 m of a planned 500 m, tap Log, and the phone recorded 500 m — the
/// anti-shame rule's exact inverse, manufacturing an achievement instead
/// of scolding a shortfall.
///
/// The distinction that fixes it is not "planned versus actual" but **who
/// knows the number**:
///
/// - Some metrics the user ASSERTS by tapping Log. A rep count, a load, a
///   damper setting, an incline: they set the machine, they did the reps,
///   and tapping the key is the claim. Carrying the planned value forward
///   is honest, and it is what "log as planned" has always meant on the
///   wrist.
/// - Some metrics the device MEASURES. Distance, pace, calories: the
///   watch either has a reading or it does not, and the plan is not
///   evidence either way.
///
/// So a measured metric is recorded when it was measured and **omitted
/// when it wasn't** — a nil actual is honest, and the phone can fill it in
/// from the console afterwards. Anything else is the user's assertion and
/// carries forward.
public enum LoggedActuals {
    /// Metrics a device reads off the world rather than the user setting
    /// them. Duration is deliberately NOT here: it is measured when a
    /// device times the effort, but a logged rep set's duration is a
    /// prescription the user honoured, so callers pass a measurement when
    /// they have one and let the planned value stand when they don't.
    public static let deviceMeasured: Set<WorkoutMetric> = [.distance, .pace, .calories]

    /// The extras bag to record, given what was planned and what was
    /// actually measured.
    ///
    /// Measurements win. Un-measured device metrics are dropped rather
    /// than inherited. Everything else — the settings and counts the user
    /// asserted — carries forward untouched.
    public static func extras(
        planned: [WorkoutMetric: Double],
        measured: [WorkoutMetric: Double] = [:]
    ) -> [WorkoutMetric: Double] {
        var actuals = planned.filter { !deviceMeasured.contains($0.key) }
        for (metric, value) in measured where value.isFinite && value > 0 {
            actuals[metric] = value
        }
        return actuals
    }

    /// Pace over one effort, from its own measured distance and elapsed
    /// time — a per-piece split rather than the whole session's average,
    /// which is what an interval workout actually wants.
    /// ⚠️ Pass the PROFILE's reference wherever you have one, exactly as
    /// `CardioTargets.derive` asks: the unit's own convention is only a
    /// fallback, and it is wrong for the case `PaceReference` exists for —
    /// a metric pool is denominated in meters and splits per 100, where
    /// the unit alone would say per 500 and print a swim's pace 5x slow.
    public static func pace(
        distance: Double?,
        elapsedSeconds: Double?,
        unit: DistanceUnit,
        paceReference: PaceReference? = nil
    ) -> Double? {
        CardioTargets.derive(
            .pace,
            distance: distance,
            durationSeconds: elapsedSeconds,
            paceSeconds: nil,
            unit: unit,
            paceReference: paceReference
        )
    }
}
