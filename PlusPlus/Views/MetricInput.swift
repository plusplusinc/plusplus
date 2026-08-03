import SwiftUI
import PlusPlusKit

/// Rep-target picking. Keyboard-free by design — the janky `.number`
/// TextFields died long ago; values are picked, never typed. (The v1
/// inline MetricRow/RepTargetRow pair that used to live here was
/// superseded by MetricStepperRow + the picker sheets and was deleted
/// as dead code in the 2026-07-15 scrubber pass.)

/// The rep target: one tape for the count, a second for the optional upper
/// bound of a range. Two wheels until 2026-07-28, when the scrubber took
/// over every measured metric and this was the last picker in the defaults
/// tray still spinning — a tray where "Reps" wheeled and every row under it
/// scrubbed was exactly the mix Dave asked to end.
///
/// ⚠️ **There is no "off" position on the upper tape, and none is needed**:
/// `RepTarget` already rules that an upper at or below the target is not a
/// range, so parking the second caret ON the first number IS "no range",
/// and pushing it right opens one ("10" → "10–14"). That's why a nil upper
/// seeds at `lower` rather than at some sentinel — an untouched sheet saves
/// back exactly what it opened with, and the left half of the tape is an
/// honest "no upper bound" rather than a dead zone.
///
/// It commits LIVE (on every scroll settle) behind a leave-only `Done`, which
/// is the same contract and the same top row as the metric picker beside it.
/// ⚠️ Both are system nav bars again as of 2026-08-02 — the thing that made
/// that wrong in 2026-07-28 was a system `Done` sitting among app-drawn sheet
/// headers, so two adjacent rows of one defaults list disagreed about what the
/// corner button meant. Every sheet is the system bar now, so the disagreement
/// is gone. What has never changed is the CONTRACT: Done means "leave", and
/// the pick has already stuck.
struct RepTargetSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Called on every settle, not once at Done — see the type comment.
    let onSave: (RepTarget) -> Void
    /// Logging contexts pass false (#246): an actual rep count is a
    /// scalar, and the range editor's upper bound was silently discarded
    /// there — a dead control during the user's first log.
    var showsUpperBound = true

    @State private var lower: Int
    @State private var upper: Int

    /// Reps scrub on the metric's own tape (whole reps, a mark each), so
    /// the count reads with the same grain here as it does on the live set
    /// screen. Both tapes share it — an upper bound is still a rep count.
    private let tape = WorkoutMetric.reps.scrubberTape()?.tape
        ?? MetricTape(range: RepTarget.allowedReps.lowerBound...RepTarget.allowedReps.upperBound,
                      pointsPerUnit: 10, minorStride: 1, labelStride: 5)

    init(target: RepTarget, showsUpperBound: Bool = true, onSave: @escaping (RepTarget) -> Void) {
        self.onSave = onSave
        self.showsUpperBound = showsUpperBound
        let seed = target.lower ?? RepTarget.defaultReps
        _lower = State(initialValue: seed)
        _upper = State(initialValue: target.upper ?? seed)
    }

    /// What the sheet is currently holding — and what each settle commits.
    /// Runs through `RepTarget`, so an upper at or below the target
    /// collapses to "no range" here exactly as it will on the way out.
    private var target: RepTarget {
        RepTarget(lower: lower, upper: showsUpperBound ? upper : nil)
    }

    var body: some View {
        NavigationStack {
        VStack(spacing: 16) {
            Text(target.display)
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(value: Double(lower)))
                .animation(Theme.Anim.standard, value: target.display)
                .accessibilityHidden(true) // the tapes speak their values

            scrubber(
                caption: showsUpperBound ? "reps" : nil,
                label: "Reps",
                unit: $lower,
                valueText: { "\($0) reps" }
            )

            if showsUpperBound {
                scrubber(
                    caption: "up to",
                    label: "Up to",
                    unit: $upper,
                    valueText: { $0 > lower ? "up to \($0) reps" : "no upper limit" }
                )
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheetChrome(
            title: "Reps",
            done: SheetAction("Done", identifier: "closeRepTargetPicker") { dismiss() }
        )
        }
        // Heights UNCHANGED: a 44 pt inline bar is SHORTER than the 68 pt
        // header it replaces (24 pt grabber clearance + a 44 pt button row),
        // so both sizes gain slack rather than clipping. Device pass.
        .presentationDetents([.height(showsUpperBound ? 430 : 320)])
        .presentationBackground(Theme.background)
    }

    private func scrubber(
        caption: String?,
        label: String,
        unit: Binding<Int>,
        valueText: @escaping (Int) -> String
    ) -> some View {
        VStack(spacing: 2) {
            if let caption {
                Text(caption)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .accessibilityHidden(true) // the scrubber carries the name
            }
            MetricScrubber(
                tape: tape,
                label: label,
                unit: unit,
                tickText: { "\($0)" },
                valueText: valueText,
                // Commit on settle, like the metric scrubber beside it. The
                // binding has already been written by the time this fires
                // (the scrubber writes `unit` first, then settles), so
                // `target` reads the landed pair, not the previous one.
                onSettle: { _ in onSave(target) }
            )
        }
    }
}
