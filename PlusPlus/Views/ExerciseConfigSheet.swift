import SwiftUI
import PlusPlusKit

/// "Configure before you do it" (Dave, 2026-07-11): the step between
/// picking an exercise and adding it to a live session. Metric rows +
/// a Sets stepper — the same grammar as the routine planning sheet
/// (`ExerciseDetailSheet.metricsCard`), bound to a `SessionExerciseConfig`
/// instead of a `RoutineExercise`. "Add to workout" commits; Cancel backs
/// out with nothing added. Prefilled from the exercise's own defaults, so
/// tapping straight through Add reproduces the old three-set behavior.
struct ExerciseConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue

    @Bindable var config: SessionExerciseConfig
    /// What the commit key says. "Add to workout" mid-session; "Start"
    /// from quick start, where the tap begins the workout rather than
    /// adding to one already running.
    var actionLabel: String = "Add to workout"
    /// Commit — append the configured block AND dismiss the picker (this
    /// stacked sheet tears down with its parent, so it must not also call
    /// its own dismiss: that would be a double-dismiss).
    let onAdd: () -> Void

    @State private var wheel: WorkoutMetric?
    @State private var showingRepsWheel = false
    @State private var showingHeartRateSheet = false
    /// Resolved once: zones drawn against Health's date of birth when
    /// readable, the fallback otherwise (same as the planning sheet).
    @State private var maxHeartRate = HealthAccess.resolvedMaxHeartRate()

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }
    private var exercise: Exercise { config.exercise }
    private var profile: MetricProfile { config.profile }

    /// What this block counts in, for the stepper label.
    /// The divider control's noun. ⚠️ `.divider`, not `?? .set`: a walk
    /// counts nothing, and offering it three SETS is the rack's word on a
    /// surface that has never been in a rack.
    private var blockUnit: WorkUnit { WorkUnit.divider(exercise.modality.workUnit) }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.borderStrong)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(exercise.name)
                        .font(.system(.title3, weight: .bold))
                        .padding(.top, 10)

                    // Every muscle group, primary first, then the gear. It
                    // wraps rather than truncating, matching the planning
                    // sheet's header.
                    FlowLayout(spacing: 6) {
                        ForEach(exercise.muscleGroups) { muscle in
                            CardTagCapsule(text: muscle.displayName)
                        }
                        CardTagCapsule(text: equipmentText)
                    }
                    .padding(.top, 8)

                    // Same header as the planning sheet: these are what
                    // you're aiming for, not a record of anything.
                    SheetSectionLabel("TARGETS")
                        .padding(.top, 16)
                    metricsCard

                    if let notes = exercise.notes {
                        NotesBlock(notes)
                            .padding(.top, 13)
                    }
                }
                .padding(.horizontal, 18)
            }

            VStack(spacing: 8) {
                Button {
                    // onAdd both appends and dismisses the picker; this
                    // sheet closes with its parent (no own dismiss).
                    onAdd()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(.footnote, weight: .bold))
                        Text(actionLabel)
                            .font(.system(.subheadline, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.raisedPrimaryKey(cornerRadius: 12))
                .accessibilityIdentifier("addConfiguredExerciseButton")

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("cancelConfigureExercise")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.appTall])
        .sheet(item: $wheel) { metric in
            MetricWheelSheet(
                metric: metric,
                weightUnit: weightUnit,
                distanceUnit: profile.distanceUnit,
                paceReference: profile.paceReference,
                value: Binding(
                    get: { config.target(metric) },
                    set: { writeTarget(metric, to: $0) }
                )
            )
        }
        .sheet(isPresented: $showingRepsWheel) {
            RepTargetSheet(
                target: RepTarget(lower: config.reps, upper: config.repsUpper)
            ) { newTarget in
                config.reps = newTarget.lower
                config.repsUpper = newTarget.upper
            }
        }
        .sheet(isPresented: $showingHeartRateSheet) {
            HeartRateTargetSheet(
                maxHeartRate: maxHeartRate,
                target: Binding(
                    get: { config.heartRateTarget },
                    set: { config.heartRateTarget = $0 }
                )
            )
        }
    }

    private var equipmentText: String {
        let names = exercise.equipment.map(\.name).sorted()
        return names.isEmpty ? "Bodyweight" : names.joined(separator: ", ")
    }

    // MARK: - Metrics

    /// One row per tracked metric (the profile decides), then the Sets
    /// stepper. A fresh config carries no stranded classic prescriptions,
    /// so `profile.metrics` is the whole story here.
    private var metricsCard: some View {
        VStack(spacing: 0) {
            ForEach(profile.metrics) { metric in
                if metric == .reps {
                    MetricStepperRow(
                        label: "Reps",
                        value: RepTarget(lower: config.reps, upper: config.repsUpper).display,
                        identifier: "cfgReps",
                        onTapValue: { showingRepsWheel = true },
                        onDecrement: { applyReps(RepTarget(lower: config.reps, upper: config.repsUpper).decremented()) },
                        onIncrement: { applyReps(RepTarget(lower: config.reps, upper: config.repsUpper).incremented()) }
                    )
                } else if metric == derivedMetric, let text = derivedText(metric) {
                    DerivedMetricRow(
                        label: metric.label,
                        value: text,
                        identifier: "cfg-\(metric.rawValue)",
                        onPromote: { promote(metric) }
                    )
                } else {
                    MetricStepperRow(
                        label: metric.label,
                        value: rowText(metric),
                        identifier: "cfg-\(metric.rawValue)",
                        onTapValue: { wheel = metric },
                        onDecrement: { stepTarget(metric, -1) },
                        onIncrement: { stepTarget(metric, 1) }
                    )
                }
                if metric == heartRateAnchor {
                    heartRateTargetRow
                }
            }
            // Stretches and static holds drop the HR prescription
            // (Exercise.showsHeartRateTargetRow owns the rule,
            // stale-target escape included). On a cardio profile it has
            // already rendered up with the work targets.
            if showsHeartRate, heartRateAnchor == nil {
                heartRateTargetRow
            }
            MetricStepperRow(
                label: blockUnit.plural.capitalized,
                value: "\(config.sets)",
                identifier: "cfgSets",
                onTapValue: nil,
                onDecrement: { config.sets = max(1, config.sets - 1) },
                onIncrement: { config.sets = min(20, config.sets + 1) }
            )
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    /// The cardio prescription (duration exercises only): opens the
    /// zone/range picker. "Off" is valid — heart-rate targets are
    /// guidance, never required.
    private var heartRateTargetRow: some View {
        Button {
            showingHeartRateSheet = true
        } label: {
            HStack(spacing: 10) {
                Text("Heart rate")
                    .font(.system(.footnote))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(config.heartRateTarget?.label(maxHeartRate: maxHeartRate) ?? "Off")
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .foregroundStyle(config.heartRateTarget == nil ? Theme.textFaint : Theme.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
        }
        .accessibilityIdentifier("cfgHeartRateTargetRow")
    }

    private func rowText(_ metric: WorkoutMetric) -> String {
        if metric == .duration {
            guard let seconds = config.durationSeconds else { return "—" }
            return DurationTape.label(for: seconds)
        }
        return metric.displayText(config.target(metric), weightUnit: weightUnit, distanceUnit: profile.distanceUnit, paceReference: profile.paceReference)
    }

    // MARK: - The two-of-three law

    /// Mirrors `ExerciseDetailSheet` — same law, same rows, bound to the
    /// config instead of the stored entry. The pair is kept parallel by
    /// hand, as `rowText`/`stepTarget`/`applyReps` already are: the shared
    /// part that could actually drift is the law itself, and that lives in
    /// Kit's `CardioTargets`.
    private var showsHeartRate: Bool {
        exercise.showsHeartRateTargetRow(existingTarget: config.heartRateTarget)
    }

    private var heartRateAnchor: WorkoutMetric? {
        guard showsHeartRate, CardioTargets.applies(to: profile) else { return nil }
        return profile.metrics.last { CardioTargets.triad.contains($0) }
    }

    private var derivedMetric: WorkoutMetric? {
        guard let metric = CardioTargets.derivedMetric(profile: profile, stored: storedTriad),
              derivedText(metric) != nil else { return nil }
        return metric
    }

    /// ⚠️ Triad reads go through this — `target(_:)` returns the extras bag
    /// whatever the profile tracks, and deriving off a metric with no row
    /// on screen produces a number the user cannot reach.
    private func storedTriad(_ metric: WorkoutMetric) -> Double? {
        profile.contains(metric) ? config.target(metric) : nil
    }

    private func derivedText(_ metric: WorkoutMetric) -> String? {
        guard let value = CardioTargets.derive(
            metric,
            distance: storedTriad(.distance),
            durationSeconds: storedTriad(.duration),
            paceSeconds: storedTriad(.pace),
            unit: profile.distanceUnit,
            paceReference: profile.paceReference
        ) else { return nil }
        if metric == .duration { return DurationTape.label(for: Int(value.rounded())) }
        return metric.displayText(value, weightUnit: weightUnit, distanceUnit: profile.distanceUnit)
    }

    /// Read the computed value BEFORE evicting — after, the inputs it is
    /// computed from are gone.
    private func promote(_ metric: WorkoutMetric) {
        let current = CardioTargets.derive(
            metric,
            distance: storedTriad(.distance),
            durationSeconds: storedTriad(.duration),
            paceSeconds: storedTriad(.pace),
            unit: profile.distanceUnit,
            paceReference: profile.paceReference
        )
        writeTarget(metric, to: current)
        wheel = metric
    }

    /// ⚠️ EVERY target write goes through this — filling the triad's last
    /// empty slot is an entry whoever made it, so the stepper and the
    /// picker evict exactly as a promotion does.
    private func writeTarget(_ metric: WorkoutMetric, to value: Double?) {
        if value != nil,
           let evicted = CardioTargets.evicted(entering: metric, profile: profile, stored: storedTriad) {
            config.setTarget(evicted, to: nil)
        }
        config.setTarget(metric, to: value)
    }

    private func stepTarget(_ metric: WorkoutMetric, _ direction: Double) {
        let stepOverride = metric == .weight ? exercise.weightStepOverride : nil
        let current = config.target(metric)
        let stepped = direction > 0
            ? metric.incremented(current, weightUnit: weightUnit, distanceUnit: profile.distanceUnit, stepOverride: stepOverride, paceReference: profile.paceReference)
            : metric.decremented(current, weightUnit: weightUnit, distanceUnit: profile.distanceUnit, stepOverride: stepOverride, paceReference: profile.paceReference)
        writeTarget(metric, to: stepped)
    }

    private func applyReps(_ target: RepTarget) {
        config.reps = target.lower
        config.repsUpper = target.upper
    }
}
