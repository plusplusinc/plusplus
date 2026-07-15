import SwiftUI
import PlusPlusKit

/// The horizontal tape scrubber for time spans (2026-07-15, after the
/// iOS 27 timer picker): drag for per-second precision, flick for real
/// scroll inertia, rubber-banding at the ends. Replaces the tiered
/// wheel for duration and rest — the wheel could only land on its own
/// 5/15/60 s grid, so a precise value like 97 s was unreachable in the
/// UI (and one wheel scroll away from being snapped to 95 s, even
/// though the interchange stores any positive whole second).
///
/// Mechanics: the physics is a real ScrollView — UIKit deceleration and
/// bounce, never hand-rolled — over an invisible strip one viewport
/// wider than the tape, so every tape offset can rest at the center
/// caret. A custom target behavior snaps the landing on a whole second;
/// the ruler itself is a viewport-sized Canvas fed by the scroll offset
/// (a 60-minute tape as real content would be a ~11,000 pt raster).
/// All numeric semantics live in Kit's `DurationTape` (Linux-tested).
///
/// Write discipline: `seconds` is the LIVE position (readout, tick
/// fill, haptics — updated per frame while the user scrolls); the model
/// commit is `onSettle`, fired once when a user-driven scroll rests.
/// Both are gated on `userTouched`, which only a user scroll phase or a
/// VoiceOver adjust can set — so opening the scrubber can never write,
/// and an out-of-range stored value (a hand-edited repo can hold a
/// 90-minute duration) displays clamped but survives untouched.
///
/// Grammar: ticks up to the picked value light in data green (the
/// value's magnitude is live data, same job as progress fills) and the
/// remainder sits in border ink; the caret is the one green pointer.
struct DurationScrubber: View {
    let tape: DurationTape
    /// VoiceOver name for the control ("Duration", "Rest").
    let label: String
    /// Live whole-second position under the caret. NOT the model write
    /// — callers commit via `onSettle` and their own dismissal hook, so
    /// a flick costs one model write, not one per frame.
    @Binding var seconds: Int
    /// Fired with the landed value when a user-driven scroll comes to
    /// rest (scroll phase returns to idle), and immediately after a
    /// VoiceOver adjust. Never fired by programmatic positioning.
    var onSettle: (Int) -> Void

    @State private var scrollPosition = ScrollPosition()
    @State private var offsetX: Double
    @State private var viewportWidth: CGFloat = 0
    /// True once the tape has been positioned on the incoming value —
    /// callbacks before that reflect the un-positioned ScrollView and
    /// would flash the lower bound through the ruler.
    @State private var settled = false
    /// True once the user has actually MOVED the tape (an .interacting
    /// scroll phase, or a VoiceOver adjust). Deliberately not .tracking:
    /// a finger that rests on the ruler and lifts without dragging must
    /// not commit the value under the caret — for an out-of-range
    /// stored value displaying clamped, that idle touch would destroy
    /// it. Programmatic scrolls never set this, so picks and commits
    /// are structurally impossible on a merely-opened scrubber,
    /// regardless of callback ordering.
    @State private var userTouched = false

    private let rulerHeight: CGFloat = 56

    init(tape: DurationTape, label: String, seconds: Binding<Int>, onSettle: @escaping (Int) -> Void) {
        self.tape = tape
        self.label = label
        _seconds = seconds
        self.onSettle = onSettle
        // The Canvas reads offsetX, not the ScrollView, so the first
        // frame already draws the incoming value under the caret.
        _offsetX = State(initialValue: tape.offset(for: seconds.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 3) {
            ruler
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
        }
        .sensoryFeedback(.selection, trigger: seconds)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(DurationTape.label(for: seconds))
        .accessibilityAdjustableAction { direction in
            let target = tape.clamped(seconds + (direction == .increment ? 1 : -1))
            guard target != seconds else { return }
            userTouched = true
            // Written synchronously so VoiceOver announces the new value
            // immediately; the scroll callback then lands on the same
            // second and no-ops.
            seconds = target
            scrollPosition.scrollTo(x: tape.offset(for: target))
            onSettle(target)
        }
        .accessibilityIdentifier("durationScrubber")
    }

    private var ruler: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Color.clear
                .frame(width: tape.length + viewportWidth, height: rulerHeight)
        }
        .frame(height: rulerHeight)
        .scrollPosition($scrollPosition)
        .scrollTargetBehavior(SecondSnap(pointsPerSecond: tape.pointsPerSecond))
        .onScrollGeometryChange(for: Double.self) { Double($0.contentOffset.x) } action: { _, new in
            guard settled else { return }
            offsetX = new
            guard userTouched else { return }
            let landed = tape.seconds(atOffset: new)
            if landed != seconds {
                seconds = landed
            }
        }
        .onScrollPhaseChange { _, newPhase in
            if newPhase == .interacting {
                userTouched = true
            } else if newPhase == .idle, userTouched {
                onSettle(seconds)
            }
        }
        .overlay { tapeCanvas.allowsHitTesting(false) }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            let firstLayout = viewportWidth == 0 && width > 0
            viewportWidth = width
            if firstLayout {
                // Position outside the layout pass. The landing callback
                // matches the seeded seconds, so nothing is written.
                Task { @MainActor in
                    scrollPosition.scrollTo(x: tape.offset(for: seconds))
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
                let x = center + (tape.offset(for: tick.seconds) - offsetX)
                // Ticks dissolve toward the viewport edges, like the
                // tape emerging from and returning to the housing.
                let fade = max(0, min(1, min(x, Double(size.width) - x) / 36))
                guard fade > 0 else { continue }
                let lit = tick.seconds <= seconds
                let bar = CGRect(x: x - 1.5, y: 24, width: 3, height: 28)
                context.fill(
                    Path(roundedRect: bar, cornerRadius: 1.5),
                    with: .color((lit ? Theme.accent : Theme.borderStrong).opacity(fade))
                )
                if let text = tick.label {
                    context.draw(
                        Text(text)
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

/// Decelerating flicks land on a whole second, never between two.
private struct SecondSnap: ScrollTargetBehavior {
    let pointsPerSecond: Double

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let x = Double(target.rect.origin.x)
        target.rect.origin.x = CGFloat((x / pointsPerSecond).rounded() * pointsPerSecond)
    }
}

/// The sheet pane pairing the scrubber with its big rolling readout.
/// Bridges the picker sheets' `Double?` binding to whole seconds: a nil
/// target shows the metric's default and commits nothing until the tape
/// actually moves — the same contract the wheel had.
struct DurationScrubberPane: View {
    let metric: WorkoutMetric
    @Binding var value: Double?

    private let tape: DurationTape
    @State private var seconds: Int
    /// The user moved the tape this presentation. The dismissal commit
    /// below fires only then, so a merely-opened pane writes nothing —
    /// nil AND out-of-range stored values survive an open-and-close.
    @State private var touched = false

    init(metric: WorkoutMetric, value: Binding<Double?>) {
        self.metric = metric
        _value = value
        let range = metric.range
        tape = DurationTape(range: Int(range.lowerBound)...Int(range.upperBound))
        // Clamped at the seed (swift-reviewer HIGH): an out-of-range
        // stored value must DISPLAY clamped — readout and caret agree —
        // but commit NOTHING until the tape moves; unclamped, the
        // settle callback would see a mismatch and silently rewrite the
        // stored value on open, the exact destroy-on-open class this
        // control removes.
        _seconds = State(initialValue: tape.clamped(Int((value.wrappedValue ?? metric.defaultValue).rounded())))
    }

    var body: some View {
        VStack(spacing: 22) {
            Text(DurationTape.label(for: seconds))
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(value: Double(seconds)))
                .animation(Theme.Anim.standard, value: seconds)
                .accessibilityHidden(true) // the scrubber speaks the value
            DurationScrubber(
                tape: tape,
                label: metric.label,
                seconds: Binding(
                    get: { seconds },
                    set: { picked in
                        seconds = picked
                        touched = true
                    }
                ),
                onSettle: { landed in
                    value = Double(landed)
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Done mid-coast or a swipe-down mid-flick must not lose the
        // landed-so-far value (the commit-in-onDisappear law: dismissal
        // paths bypass everything else). Idempotent with onSettle.
        .onDisappear {
            if touched {
                value = Double(seconds)
            }
        }
    }
}
