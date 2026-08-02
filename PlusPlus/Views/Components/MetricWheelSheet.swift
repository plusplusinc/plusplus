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
/// ⚠️ The top row is a `NavigationStack` toolbar again (2026-08-02),
/// reversing 2026-07-28. That reversal was RIGHT at the time and its reason
/// has expired: the tray wore a system bar with an accent-green `Done` while
/// every sheet around it wore the app's own header, so the tray you open FROM
/// the exercise editor answered in a different button vocabulary than the
/// sheet that opened it. Now every sheet wears the system bar, so the system
/// bar IS the shared vocabulary — the mismatch inverted. Done still means
/// "leave", never "save": the value commits live (the scrubber writes on
/// settle, the wheel on selection).
struct MetricWheelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let metric: WorkoutMetric
    var weightUnit: WeightUnit = .lb
    var distanceUnit: DistanceUnit = .meters
    /// The profile's pace denominator, when it overrides its unit's own.
    /// Carried so a swim's split reads /100yd on the picker as well as on
    /// the row that opened it.
    var paceReference: PaceReference?
    @Binding var value: Double?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if metric.usesTapeScrubber {
                    MetricScrubberPane(metric: metric, weightUnit: weightUnit, distanceUnit: distanceUnit, paceReference: paceReference, value: $value)
                } else {
                    wheel
                }
            }
            .sheetChrome(
                title: metric.label,
                done: SheetAction("Done", identifier: "closeMetricPicker") { dismiss() }
            )
        }
        // ⚠️ 320 is UNCHANGED, and that is a measurement rather than an
        // oversight: the header this replaced was 24 pt of grabber clearance
        // plus a 44 pt button row, so a 44 pt inline nav bar hands ~24 pt BACK
        // to the scrubber. Device pass — if anything is wrong here it is slack,
        // not clipping.
        .presentationDetents([.height(320)])
        .presentationBackground(Theme.background)
    }

    private var wheel: some View {
        Picker(metric.label, selection: Binding(
            get: { metric.nearestWheelValue(to: value, weightUnit: weightUnit, distanceUnit: distanceUnit, paceReference: paceReference) },
            set: { value = $0 }
        )) {
            ForEach(metric.wheelValues(weightUnit: weightUnit, distanceUnit: distanceUnit, paceReference: paceReference), id: \.self) { candidate in
                Text(metric.displayText(candidate, weightUnit: weightUnit, distanceUnit: distanceUnit, paceReference: paceReference))
                    .font(.system(.body, design: .monospaced))
                    .tag(candidate)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxHeight: .infinity)
    }
}
