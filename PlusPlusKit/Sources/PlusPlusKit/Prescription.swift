import Foundation

/// One run of a rendered prescription, tagged with the field it states.
///
/// The Today ledger prints a prescription beside the last performance of it
/// and lights the part that moved. Doing that over a finished string means
/// computing character ranges and keeping them correct through unit changes,
/// rep ranges and a negative assist load. Runs make it a lookup instead:
/// `RoutineDiff.changedFields` returns `.metric(.weight)`, and the run
/// carrying that field is the one drawn bright.
public struct PrescriptionRun: Equatable, Sendable {
    public var text: String
    /// The field this run states, or nil for the separators between them
    /// ("×", " @ "), which belong to no field and are never emphasized.
    public var field: RoutineDiff.Field?

    public init(_ text: String, _ field: RoutineDiff.Field? = nil) {
        self.text = text
        self.field = field
    }
}

/// How a prescription reads on the Today ledger: "3×8 @ 135 lb", split into
/// styleable runs. Pure formatting, so it is unit-tested on Linux rather
/// than eyeballed in a simulator.
public enum Prescription {
    /// One field's value as the ledger shows it.
    ///
    /// This is the ONE place assistance renders as a NEGATIVE load. It is
    /// stored as a positive number that helps, with an improvement direction
    /// of `.down`, which makes it the odd one out among loads. Shown signed
    /// it rejoins weight on a single axis where a bigger number is always
    /// the harder session, and the whole progression from assisted to
    /// weighted becomes one continuous line: −35, −25, 0, +10.
    ///
    /// Deliberately NOT done in `WorkoutMetric.displayText` (Dave, 2026-07-27):
    /// that backs the metric wheels and ± steppers, whose stored range is
    /// 0...500 and whose increment would then appear to move toward zero.
    /// The cost accepted here is that the ledger says "−25 lb" where the
    /// exercise sheet still says "25 Assist".
    public static func text(
        for field: RoutineDiff.Field,
        value: Double,
        repsUpper: Int? = nil,
        distanceUnit: DistanceUnit = .meters,
        weightUnit: WeightUnit = .lb
    ) -> String {
        switch field {
        case .sets:
            return String(Int(value.rounded()))
        case .metric(.reps):
            // The bare target ("8", "8–10"), never "8 reps": inside a block
            // the "×" already says what it is, and in a metric row the row's
            // own label does. Routing both through here is also what keeps a
            // RANGE from collapsing to its lower bound on one path only.
            return RepTarget(lower: Int(value.rounded()), upper: repsUpper).display
        case .metric(.assistance):
            return "−" + WorkoutMetric.assistance.displayText(
                abs(value), weightUnit: weightUnit, distanceUnit: distanceUnit
            )
        case .metric(let metric):
            return metric.displayText(value, weightUnit: weightUnit, distanceUnit: distanceUnit)
        }
    }

    /// The staged prescription: "3" "×" "8" " @ " "135 lb".
    public static func blockRuns(
        target: RoutineDiff.Target,
        profile: MetricProfile,
        weightUnit: WeightUnit = .lb
    ) -> [PrescriptionRun] {
        runs(
            sets: target.sets,
            reps: target.reps,
            repsUpper: target.repsUpper,
            weight: target.weight,
            durationSeconds: target.durationSeconds,
            extras: target.extras,
            profile: profile,
            weightUnit: weightUnit
        )
    }

    /// The same shape for what actually happened, so the two columns line up
    /// token for token. An actual is always a single rep count, never a
    /// range, so there is no upper to pass.
    public static func blockRuns(
        prior: RoutineDiff.Prior,
        profile: MetricProfile,
        weightUnit: WeightUnit = .lb
    ) -> [PrescriptionRun] {
        runs(
            sets: prior.sets,
            reps: prior.reps,
            repsUpper: nil,
            weight: prior.weight,
            durationSeconds: prior.durationSeconds,
            extras: prior.extras,
            profile: profile,
            weightUnit: weightUnit
        )
    }

    static func runs(
        sets: Int?,
        reps: Int?,
        repsUpper: Int?,
        weight: Double?,
        durationSeconds: Int?,
        extras: [WorkoutMetric: Double],
        profile: MetricProfile,
        weightUnit: WeightUnit
    ) -> [PrescriptionRun] {
        var out: [PrescriptionRun] = []
        if let sets {
            out.append(PrescriptionRun(text(for: .sets, value: Double(sets)), .sets))
        }

        guard profile.tracksReps else {
            // Cardio blocks state rounds × the work target: "4× 500 m",
            // "3× 20:00". The driver is whichever work metric the profile
            // tracks and this block actually carries.
            let driver = profile.driver { stored($0, reps: reps, weight: weight, durationSeconds: durationSeconds, extras: extras) }
            if let value = stored(driver, reps: reps, weight: weight, durationSeconds: durationSeconds, extras: extras) {
                if !out.isEmpty { out.append(PrescriptionRun("× ")) }
                out.append(PrescriptionRun(
                    text(for: .metric(driver), value: value, distanceUnit: profile.distanceUnit, weightUnit: weightUnit),
                    .metric(driver)
                ))
            }
            return out
        }

        if let reps {
            if !out.isEmpty { out.append(PrescriptionRun("×")) }
            // RepTarget normalizes an inverted range away, so the raw
            // `repsUpper` column is safe to hand over unchecked.
            out.append(PrescriptionRun(
                text(for: .metric(.reps), value: Double(reps), repsUpper: repsUpper),
                .metric(.reps)
            ))
        }

        // The load slot takes assistance when the profile tracks it, weight
        // otherwise — one value, one slot. The routine card's previous
        // formatter read the weight column only, so an assisted exercise
        // rendered a bare "3×6" with no load shown at all.
        let load: (field: RoutineDiff.Field, value: Double)?
        if profile.contains(.assistance), let assist = extras[.assistance] {
            load = (.metric(.assistance), assist)
        } else if let weight, weight > 0 {
            load = (.metric(.weight), weight)
        } else {
            load = nil
        }
        if let load {
            if !out.isEmpty { out.append(PrescriptionRun(" @ ")) }
            out.append(PrescriptionRun(
                text(for: load.field, value: load.value, distanceUnit: profile.distanceUnit, weightUnit: weightUnit),
                load.field
            ))
        }
        return out
    }

    /// Where a metric's value lives across the column/bag split, mirroring
    /// `RoutineDiff.Target.value(for:)` for the loose values this builder
    /// takes.
    private static func stored(
        _ metric: WorkoutMetric,
        reps: Int?,
        weight: Double?,
        durationSeconds: Int?,
        extras: [WorkoutMetric: Double]
    ) -> Double? {
        switch metric {
        case .weight: return weight
        case .reps: return reps.map(Double.init)
        case .duration: return durationSeconds.map(Double.init)
        default: return extras[metric]
        }
    }
}
