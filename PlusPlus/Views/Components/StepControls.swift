import SwiftUI
import PlusPlusKit

/// The app's ONE configuration icon button (#391, Dave 2026-07-16): a small
/// `slider.horizontal.3` key that opens a sheet to configure how a value
/// behaves in place — today the per-metric stepper increment on the set
/// screen. Standardized here so every "configure this" affordance across the
/// app reads the same: reach for THIS, never a bespoke gear/ellipsis glyph,
/// whenever the job is "adjust how this value works". `slider.horizontal.3`
/// is iOS's conventional adjust-settings glyph; `ellipsis` stays the options
/// MENU affordance, so the two don't collide. 28 pt cap on a 44 pt hit
/// target (#130 floor).
struct ConfigIconButton: View {
    /// The one symbol every configuration icon button draws. Change it here
    /// and the whole app moves together.
    static let symbol = "slider.horizontal.3"

    let accessibilityLabel: String
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: Self.symbol)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                // Visual 30 pt, hit target 44 pt (the excess falls into the
                // card's corner padding, so the row never inflates).
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier ?? "configIncrementButton")
    }
}

/// A stepper key that fires once on tap and REPEATS while held (Dave,
/// 2026-07-16) — press and hold to keep stepping until release. Same raised
/// cap + mono step label as the rest of the set screen.
///
/// The tap stays a plain `Button` (reliable, accessible, and what XCUITest
/// drives); the hold rides ONE `.onLongPressGesture(perform:onPressingChanged:)`.
/// `perform` fires at the 0.3 s threshold (while still pressed) to start the
/// repeat; `onPressingChanged(false)` fires on BOTH release AND cancellation —
/// so when a scrolling ancestor steals the touch, the repeat still stops
/// (a bare `DragGesture.onEnded` never fires on cancel, which would leak the
/// task and let the value climb on its own — swift-reviewer). `maximumDistance`
/// cancels the press if the finger travels into a scroll, so a pan never
/// starts a repeat. A completed hold sets `didRepeat` so the Button's
/// trailing tap-up doesn't append one extra step. ⚠️ Gesture-layer behavior
/// isn't exercisable by XCUITest (taps bypass the gesture overlay) — needs an
/// on-device pass.
struct HoldRepeatKey: View {
    let label: String
    var height: CGFloat = 56
    var width: CGFloat? = nil
    let identifier: String
    let onStep: () -> Void

    @State private var repeatTask: Task<Void, Never>?
    /// True once a hold has begun repeating, so the Button's tap-up on release
    /// is swallowed instead of adding a stray step. Reset when the next press
    /// begins (and defensively when the swallow happens).
    @State private var didRepeat = false
    /// The hold's on-screen echo (#504, b4): the mechanism had none — a
    /// held key looked exactly like a resting one while the value climbed.
    /// While repeating the cap wears the raised fill and a data-green
    /// stroke (green is data in motion), dropping back on release/cancel.
    @State private var repeating = false

    var body: some View {
        Button {
            if didRepeat { didRepeat = false; return }
            onStep()
        } label: {
            Text(label)
                .font(.system(.body, design: .monospaced, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .frame(width: width, height: height)
                .background(repeating ? Theme.surfaceRaised : Theme.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(repeating ? Theme.accent : Theme.borderStrong))
                .animation(Theme.Anim.press, value: repeating)
        }
        .buttonStyle(.raisedKey(cornerRadius: 12))
        .accessibilityIdentifier(identifier)
        .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 24, perform: {
            beginRepeat()
        }, onPressingChanged: { pressing in
            if pressing {
                didRepeat = false
            } else {
                // Release OR cancel (scroll steal) — always stops the repeat.
                endRepeat()
            }
        })
        // A hold in flight must not outlive the screen (the deferred-beat
        // rule): cancel if this key disappears mid-press.
        .onDisappear { endRepeat() }
    }

    private func beginRepeat() {
        endRepeat()
        didRepeat = true
        repeating = true
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.prepare()
        repeatTask = Task { @MainActor in
            // First tick fires the instant the hold registers, then the
            // stride repeats ~12/s until release. Each tick clamps at the
            // metric's range bound via the caller, so a maxed value simply
            // stops moving.
            while !Task.isCancelled {
                haptic.impactOccurred(intensity: 0.55)
                onStep()
                try? await Task.sleep(for: .seconds(0.085))
            }
        }
    }

    private func endRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
        repeating = false
    }
}

/// The increment sheet (#391): opened from a metric card's `ConfigIconButton`,
/// it offers the metric's plate-shaped stride presets (Kit `stepChoices`) as
/// tappable chips, the current one lit. Picking one persists it and dismisses.
/// Presented only for the load metrics (weight/assist), whose stride has an
/// equipment home to persist into — hence the "saved to your equipment" note.
struct IncrementSheet: View {
    let metric: WorkoutMetric
    let weightUnit: WeightUnit
    let distanceUnit: DistanceUnit
    /// The profile's pace denominator, when it overrides its unit's own.
    /// Carried so a swim's split reads /100yd on the picker as well as on
    /// the row that opened it.
    var paceReference: PaceReference?
    /// The stride currently in force (resolved), so it reads as selected even
    /// when it's a custom gear value outside the presets.
    let current: Double
    let onPick: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    private var choices: [Double] {
        var values = metric.stepChoices(weightUnit: weightUnit, distanceUnit: distanceUnit, paceReference: paceReference)
        if !values.contains(current) { values.append(current) }
        return values.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // A tray leads with a SheetHeader title and a text dismissal
            // key, like every other tray (2026-07-28). This one led with an
            // ALL-CAPS mono label — which is the SECTION vocabulary, not the
            // title one — and offered no way out but a swipe, so it was the
            // only tray in the app with nothing in its top-right corner.
            // `closeOnly` because picking a chip IS the action and dismisses.
            SheetHeader(
                title: "Increment",
                actionLabel: "Done",
                actionIdentifier: "closeIncrementSheet",
                closeOnly: true
            ) {
                dismiss()
            }
            Text("How much each step changes \(metric.label.lowercased()).")
                .font(.system(.subheadline))
                .foregroundStyle(Theme.textSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 10)], spacing: 10) {
                ForEach(choices, id: \.self) { choice in
                    chip(choice)
                }
            }

            // The stride lives on your gear, so the change sticks and travels
            // with the equipment (never a silent one-workout override).
            Text("Saved to your equipment, so it sticks next time.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textFaint)
            Spacer(minLength: 0)
        }
        // Horizontal + bottom only: `SheetHeader` carries its own 24 pt of
        // grabber clearance, and stacking a container top inset on that
        // pushes the title twice as far down as every other tray's.
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // One detent, so no explicit drag indicator: the system shows a
        // grabber exactly when a sheet is resizable, and this now matches
        // the two other fixed-size pickers (metric, reps). It had `.medium`
        // as a second detent, which is a FRACTION of the screen and lands
        // BELOW 360 on a small phone, so "expanding" the sheet shrank it.
        .presentationDetents([.height(360)])
        .background(Theme.background)
    }

    private func chip(_ choice: Double) -> some View {
        let active = choice == current
        return Button {
            onPick(choice)
            dismiss()
        } label: {
            Text(metric.displayText(choice, weightUnit: weightUnit, distanceUnit: distanceUnit, paceReference: paceReference))
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                // Blue, not green (Dave, 2026-07-28): the values are data,
                // but the state being expressed is SELECTION, and every
                // other selectable control says that in blue.
                .foregroundStyle(active ? Theme.selectedInk : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .background(active ? Theme.selectedTint : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? Theme.selectedRing : Theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("incrementChoice-\(metric.formatted(choice))")
    }
}
