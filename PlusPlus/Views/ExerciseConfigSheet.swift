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

                    HStack(spacing: 6) {
                        ChipLabel(exercise.muscleGroup.displayName)
                        ChipLabel(equipmentText)
                    }
                    .padding(.top, 8)

                    metricsCard
                        .padding(.top, 12)

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
                        Text("Add to workout")
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
        .presentationBackground(Theme.surface)
        .presentationDetents([.fraction(0.7), .large])
        .sheet(item: $wheel) { metric in
            MetricWheelSheet(
                metric: metric,
                weightUnit: weightUnit,
                distanceUnit: profile.distanceUnit,
                value: Binding(
                    get: { config.target(metric) },
                    set: { config.setTarget(metric, to: $0) }
                )
            )
        }
        .sheet(isPresented: $showingRepsWheel) {
            RepTargetWheelSheet(
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
            }
            if profile.legacyType == .duration {
                heartRateTargetRow
            }
            MetricStepperRow(
                label: "Sets",
                value: "\(config.sets)",
                identifier: "cfgSets",
                onTapValue: nil,
                onDecrement: { config.sets = max(1, config.sets - 1) },
                onIncrement: { config.sets = min(20, config.sets + 1) }
            )
        }
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
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
                Text("Target HR")
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
            return seconds >= 60 ? WorkoutMetric.duration.formatted(Double(seconds)) : "\(seconds)s"
        }
        return metric.displayText(config.target(metric), weightUnit: weightUnit, distanceUnit: profile.distanceUnit)
    }

    private func stepTarget(_ metric: WorkoutMetric, _ direction: Double) {
        let stepOverride = metric == .weight ? exercise.weightStepOverride : nil
        let current = config.target(metric)
        let stepped = direction > 0
            ? metric.incremented(current, weightUnit: weightUnit, distanceUnit: profile.distanceUnit, stepOverride: stepOverride)
            : metric.decremented(current, weightUnit: weightUnit, distanceUnit: profile.distanceUnit, stepOverride: stepOverride)
        config.setTarget(metric, to: stepped)
    }

    private func applyReps(_ target: RepTarget) {
        config.reps = target.lower
        config.repsUpper = target.upper
    }
}
