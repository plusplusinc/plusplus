import SwiftUI
import PlusPlusKit

/// Picker sheet for any stepped metric, v2 styling. Wide continuous
/// metrics — the time spans (duration, rest, transition) plus distance
/// and calories — open the horizontal tape scrubber, where every whole
/// unit is reachable; loads, short lists (reps), and machine dials keep
/// the single tiered wheel (`usesTapeScrubber` owns the split). Lived
/// inside ExerciseDetailSheet.swift until the scrubber split
/// (2026-07-15); it is presented from four screens, so it belongs here.
struct MetricWheelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let metric: WorkoutMetric
    var weightUnit: WeightUnit = .lb
    var distanceUnit: DistanceUnit = .meters
    @Binding var value: Double?

    var body: some View {
        NavigationStack {
            Group {
                if metric.usesTapeScrubber {
                    MetricScrubberPane(metric: metric, weightUnit: weightUnit, distanceUnit: distanceUnit, value: $value)
                } else {
                    wheel
                }
            }
            .navigationTitle(metric.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationDetents([.height(300)])
        .presentationBackground(Theme.surface)
    }

    private var wheel: some View {
        Picker(metric.label, selection: Binding(
            get: { metric.nearestWheelValue(to: value, weightUnit: weightUnit, distanceUnit: distanceUnit) },
            set: { value = $0 }
        )) {
            ForEach(metric.wheelValues(weightUnit: weightUnit, distanceUnit: distanceUnit), id: \.self) { candidate in
                Text(metric.displayText(candidate, weightUnit: weightUnit, distanceUnit: distanceUnit))
                    .font(.system(.body, design: .monospaced))
                    .tag(candidate)
            }
        }
        .pickerStyle(.wheel)
    }
}
