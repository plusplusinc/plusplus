import SwiftUI
import PlusPlusKit

/// Picker sheet for any stepped metric, v2 styling. MEASURED metrics open
/// the horizontal tape scrubber, where every whole unit is reachable — as
/// of 2026-07-28 that is all of them but two, so the wheel below now
/// serves only the enumerated scales (machine resistance levels, RPE).
/// `usesTapeScrubber` owns the line and the reasoning. Lived inside
/// ExerciseDetailSheet.swift until the scrubber split (2026-07-15); it is
/// presented from five screens, so it belongs here.
///
/// The top row is the app's `SheetHeader`, not a `NavigationStack`'s
/// toolbar (2026-07-28). It wore a system nav bar with an accent-green
/// `Done` for as long as it existed, which meant the tray you open FROM
/// the exercise editor's defaults list answered in a different button
/// vocabulary than the sheet that opened it. `closeOnly` because the value
/// commits live — the scrubber writes on settle, the wheel on selection —
/// so Done here means "leave", never "save".
struct MetricWheelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let metric: WorkoutMetric
    var weightUnit: WeightUnit = .lb
    var distanceUnit: DistanceUnit = .meters
    @Binding var value: Double?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: metric.label,
                actionLabel: "Done",
                actionIdentifier: "closeMetricPicker",
                closeOnly: true
            ) {
                dismiss()
            }
            .padding(.horizontal, 18)

            if metric.usesTapeScrubber {
                MetricScrubberPane(metric: metric, weightUnit: weightUnit, distanceUnit: distanceUnit, value: $value)
            } else {
                wheel
            }
        }
        .presentationDetents([.height(320)])
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
        .frame(maxHeight: .infinity)
    }
}
