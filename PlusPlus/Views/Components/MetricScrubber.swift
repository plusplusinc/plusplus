import SwiftUI
import PlusPlusKit

/// The horizontal tape scrubber for a continuous metric (2026-07-15, after
/// the iOS 27 timer picker; generalized past time to distance and calories
/// 2026-07-19): drag for per-unit precision, flick for real scroll inertia,
/// rubber-banding at the ends. Replaces the tiered wheel wherever a value
/// lives on a wide continuous range — the wheel could only land on its own
/// coarse grid, so a precise value (97 s, 3.14 mi, a 137-cal target) was
/// unreachable in the UI, and one wheel scroll away from being snapped to a
/// nearby grid point even though the interchange stores any value.
///
/// Mechanics: the physics is a real ScrollView — UIKit deceleration and
/// bounce, never hand-rolled — over an invisible strip one viewport wider
/// than the tape, so every tape offset can rest at the center caret. A
/// custom target behavior snaps the landing on a whole unit; the ruler
/// itself is a viewport-sized Canvas fed by the scroll offset (a long tape
/// as real content would be a huge raster). All numeric semantics live in
/// Kit's `MetricTape` (Linux-tested); the "unit" is the tape's smallest
/// step (1 s, 1 m, 0.01 mi, 1 cal), which the pane maps to the metric's
/// real value.
///
/// Write discipline: `unit` is the LIVE position (readout, tick fill,
/// haptics — updated per frame while the user scrolls); the model commit is
/// `onSettle`, fired once when a user-driven scroll rests. Both are gated on
/// `userTouched`, which only a user scroll phase or a VoiceOver adjust can
/// set — so opening the scrubber can never write, and an out-of-range
/// stored value (a hand-edited repo can hold one) displays clamped but
/// survives untouched.
///
/// Grammar: ticks up to the picked value light in data green (the value's
/// magnitude is live data, same job as progress fills) and the remainder
/// sits in border ink; the caret is the one green pointer.
struct MetricScrubber: View {
    let tape: MetricTape
    /// VoiceOver name for the control ("Duration", "Distance", "Calories").
    let label: String
    /// Units per VoiceOver adjust step — 1 s for time, but a coarser real
    /// increment for the wide metrics (50 m, 0.25 mi, 5 cal) so an
    /// accessibility swipe moves a meaningful amount, not one hundredth.
    let adjustStep: Int
    /// Live whole-unit position under the caret. NOT the model write —
    /// callers commit via `onSettle` and their own dismissal hook, so a
    /// flick costs one model write, not one per frame.
    @Binding var unit: Int
    /// Text for a LABELED tick, given its unit (the metric's formatted
    /// value: "1:00", "0.5", "250").
    var tickText: (Int) -> String
    /// The current value spoken by VoiceOver, given the unit.
    var valueText: (Int) -> String
    /// Fired with the landed unit when a user-driven scroll comes to rest
    /// (scroll phase returns to idle), and immediately after a VoiceOver
    /// adjust. Never fired by programmatic positioning.
    var onSettle: (Int) -> Void

    @State private var scrollPosition = ScrollPosition()
    @State private var offsetX: Double
    @State private var viewportWidth: CGFloat = 0
    /// True once the tape has been positioned on the incoming value —
    /// callbacks before that reflect the un-positioned ScrollView and would
    /// flash the lower bound through the ruler.
    @State private var settled = false
    /// True once the user has actually MOVED the tape (an .interacting
    /// scroll phase, or a VoiceOver adjust). Deliberately not .tracking: a
    /// finger that rests on the ruler and lifts without dragging must not
    /// commit the value under the caret — for an out-of-range stored value
    /// displaying clamped, that idle touch would destroy it. Programmatic
    /// scrolls never set this, so picks and commits are structurally
    /// impossible on a merely-opened scrubber, regardless of callback
    /// ordering.
    @State private var userTouched = false

    private let rulerHeight: CGFloat = 56

    init(
        tape: MetricTape,
        label: String,
        adjustStep: Int = 1,
        unit: Binding<Int>,
        tickText: @escaping (Int) -> String,
        valueText: @escaping (Int) -> String,
        onSettle: @escaping (Int) -> Void
    ) {
        self.tape = tape
        self.label = label
        self.adjustStep = max(adjustStep, 1)
        _unit = unit
        self.tickText = tickText
        self.valueText = valueText
        self.onSettle = onSettle
        // The Canvas reads offsetX, not the ScrollView, so the first frame
        // already draws the incoming value under the caret.
        _offsetX = State(initialValue: tape.offset(for: unit.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 3) {
            ruler
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
        }
        .sensoryFeedback(.selection, trigger: unit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(valueText(unit))
        .accessibilityAdjustableAction { direction in
            let target = tape.clamped(unit + (direction == .increment ? adjustStep : -adjustStep))
            guard target != unit else { return }
            userTouched = true
            // Written synchronously so VoiceOver announces the new value
            // immediately; the scroll callback then lands on the same unit
            // and no-ops.
            unit = target
            scrollPosition.scrollTo(x: tape.offset(for: target))
            onSettle(target)
        }
        .accessibilityIdentifier("metricScrubber")
    }

    private var ruler: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Color.clear
                .frame(width: tape.length + viewportWidth, height: rulerHeight)
        }
        .frame(height: rulerHeight)
        .scrollPosition($scrollPosition)
        .scrollTargetBehavior(UnitSnap(pointsPerUnit: tape.pointsPerUnit))
        .onScrollGeometryChange(for: Double.self) { Double($0.contentOffset.x) } action: { _, new in
            guard settled else { return }
            offsetX = new
            guard userTouched else { return }
            let landed = tape.unit(atOffset: new)
            if landed != unit {
                unit = landed
            }
        }
        .onScrollPhaseChange { _, newPhase in
            if newPhase == .interacting {
                userTouched = true
            } else if newPhase == .idle, userTouched {
                onSettle(unit)
            }
        }
        .overlay { tapeCanvas.allowsHitTesting(false) }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            let firstLayout = viewportWidth == 0 && width > 0
            viewportWidth = width
            if firstLayout {
                // Position outside the layout pass. The landing callback
                // matches the seeded unit, so nothing is written.
                Task { @MainActor in
                    scrollPosition.scrollTo(x: tape.offset(for: unit))
                    settled = true
                }
            }
        }
    }

    private var tapeCanvas: some View {
        Canvas { context, size in
            let center = Double(size.width) / 2
            let window = (offsetX - center)...(offsetX + center)
            for tick in tape.ticks(in: window) {
                let x = center + (tape.offset(for: tick.unit) - offsetX)
                // Ticks dissolve toward the viewport edges, like the tape
                // emerging from and returning to the housing.
                let fade = max(0, min(1, min(x, Double(size.width) - x) / 36))
                guard fade > 0 else { continue }
                let lit = tick.unit <= unit
                let bar = CGRect(x: x - 1.5, y: 24, width: 3, height: 28)
                context.fill(
                    Path(roundedRect: bar, cornerRadius: 1.5),
                    with: .color((lit ? Theme.accent : Theme.borderStrong).opacity(fade))
                )
                if tick.isLabeled {
                    context.draw(
                        Text(tickText(tick.unit))
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                            .foregroundStyle((lit ? Theme.textSecondary : Theme.textFaint).opacity(fade)),
                        at: CGPoint(x: x, y: 10)
                    )
                }
            }
        }
        .frame(height: rulerHeight)
    }
}

/// Decelerating flicks land on a whole unit, never between two.
private struct UnitSnap: ScrollTargetBehavior {
    let pointsPerUnit: Double

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let x = Double(target.rect.origin.x)
        target.rect.origin.x = CGFloat((x / pointsPerUnit).rounded() * pointsPerUnit)
    }
}

/// The sheet pane pairing the scrubber with its big rolling readout.
/// Bridges the picker sheets' `Double?` binding to whole tape units: a nil
/// target shows the metric's default and commits nothing until the tape
/// actually moves — the same contract the wheel had. Time spans read their
/// value as clock text (m:ss); distance and calories read as the metric's
/// value plus unit ("1.5 mi", "300 cal").
struct MetricScrubberPane: View {
    let metric: WorkoutMetric
    var weightUnit: WeightUnit = .lb
    var distanceUnit: DistanceUnit = .meters
    @Binding var value: Double?

    private let tape: MetricTape
    /// Tape units per one unit of the metric's real value — the reciprocal
    /// of the quantum, as a whole number (1 for 1 s/1 m/1 cal, 100 for the
    /// 0.01 mi/km grid). Dividing unit→value by this (rather than
    /// multiplying by 0.01) keeps the committed value the exact double the
    /// readout shows, so a diff never sees phantom last-bit drift.
    private let unitsPerValue: Double
    private let adjustStep: Int
    @State private var unit: Int
    /// The user moved the tape this presentation. The dismissal commit below
    /// fires only then, so a merely-opened pane writes nothing — nil AND
    /// out-of-range stored values survive an open-and-close.
    @State private var touched = false

    init(metric: WorkoutMetric, weightUnit: WeightUnit = .lb, distanceUnit: DistanceUnit = .meters, value: Binding<Double?>) {
        self.metric = metric
        self.weightUnit = weightUnit
        self.distanceUnit = distanceUnit
        _value = value
        // Present only for metrics that scrub (`usesTapeScrubber`), so the
        // factory always yields a tape here; the fallback keeps the init
        // total in the impossible case rather than force-unwrapping.
        let spec = metric.scrubberTape(distanceUnit: distanceUnit)
            ?? (quantum: 1, tape: MetricTape(range: 0...1, pointsPerUnit: 1, minorStride: 1, labelStride: 1))
        tape = spec.tape
        let perValue = (1 / spec.quantum).rounded()
        unitsPerValue = perValue
        // A meaningful VoiceOver stride: the metric's real stepper increment
        // in units, but time spans stay at one second (their historical
        // adjust feel), never a 15 s jump.
        adjustStep = metric.isTimeSpan
            ? 1
            : max(1, Int((metric.step(weightUnit: weightUnit, distanceUnit: distanceUnit) * perValue).rounded()))
        // Clamped at the seed (swift-reviewer HIGH): an out-of-range stored
        // value must DISPLAY clamped — readout and caret agree — but commit
        // NOTHING until the tape moves; unclamped, the settle callback would
        // see a mismatch and silently rewrite the stored value on open, the
        // exact destroy-on-open class this control removes.
        let seed = (value.wrappedValue ?? metric.defaultValue(weightUnit: weightUnit, distanceUnit: distanceUnit)) * perValue
        _unit = State(initialValue: spec.tape.clamped(Int(seed.rounded())))
    }

    /// The metric's real value for a tape unit — division, so 0.01-grid
    /// values are the canonical double, not `unit * 0.01`.
    private func metricValue(forUnit unit: Int) -> Double {
        Double(unit) / unitsPerValue
    }

    /// Big readout: clock text for time spans, value-plus-unit otherwise.
    private func readout(_ unit: Int) -> String {
        metric.isTimeSpan
            ? DurationTape.label(for: unit)
            : metric.displayText(metricValue(forUnit: unit), weightUnit: weightUnit, distanceUnit: distanceUnit)
    }

    /// Tick label: the bare formatted number (the readout carries the unit),
    /// or clock text for time spans.
    private func tickText(_ unit: Int) -> String {
        metric.isTimeSpan
            ? DurationTape.label(for: unit)
            : metric.formatted(metricValue(forUnit: unit))
    }

    var body: some View {
        VStack(spacing: 22) {
            Text(readout(unit))
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(value: Double(unit)))
                .animation(Theme.Anim.standard, value: unit)
                .accessibilityHidden(true) // the scrubber speaks the value
            MetricScrubber(
                tape: tape,
                label: metric.label,
                adjustStep: adjustStep,
                unit: Binding(
                    get: { unit },
                    set: { picked in
                        unit = picked
                        touched = true
                    }
                ),
                tickText: tickText,
                valueText: readout,
                onSettle: { landed in
                    value = metricValue(forUnit: landed)
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Done mid-coast or a swipe-down mid-flick must not lose the
        // landed-so-far value (the commit-in-onDisappear law: dismissal
        // paths bypass everything else). Idempotent with onSettle.
        .onDisappear {
            if touched {
                value = metricValue(forUnit: unit)
            }
        }
    }
}
