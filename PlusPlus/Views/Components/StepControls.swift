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
/// The tap stays a plain `Button` (reliable, and what XCUITest drives); the
/// hold rides two SIMULTANEOUS gestures so neither starves the enclosing
/// scroll (.claude/rules/ui-interaction.md warns a sequenced long-press/drag
/// does): a 0.3 s long-press starts the repeat, a 0-distance drag's end stops
/// it, and a scroll's movement past 24 pt cancels the long-press before it
/// can fire. ⚠️ Gesture-layer behavior isn't exercisable by XCUITest (taps
/// bypass the gesture overlay) — needs an on-device pass.
struct HoldRepeatKey: View {
    let label: String
    var height: CGFloat = 56
    var width: CGFloat? = nil
    let identifier: String
    let onStep: () -> Void

    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Button(action: onStep) {
            Text(label)
                .font(.system(.body, design: .monospaced, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .frame(width: width, height: height)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(.raisedKey(cornerRadius: 12))
        .accessibilityIdentifier(identifier)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3, maximumDistance: 24)
                .onEnded { _ in beginRepeat() }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in endRepeat() }
        )
        // A hold in flight must not outlive the screen (the deferred-beat
        // rule): cancel if this key disappears mid-press.
        .onDisappear { endRepeat() }
    }

    private func beginRepeat() {
        endRepeat()
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
    /// The stride currently in force (resolved), so it reads as selected even
    /// when it's a custom gear value outside the presets.
    let current: Double
    let onPick: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    private var choices: [Double] {
        var values = metric.stepChoices(weightUnit: weightUnit, distanceUnit: distanceUnit)
        if !values.contains(current) { values.append(current) }
        return values.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("INCREMENT")
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .kerning(0.7)
                    .foregroundStyle(Theme.textSecondary)
                Text("How much each step changes \(metric.label.lowercased()).")
                    .font(.system(.subheadline))
                    .foregroundStyle(Theme.textSecondary)
            }

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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(300), .medium])
        .presentationDragIndicator(.visible)
        .background(Theme.background)
    }

    private func chip(_ choice: Double) -> some View {
        let active = choice == current
        return Button {
            onPick(choice)
            dismiss()
        } label: {
            Text(metric.displayText(choice, weightUnit: weightUnit, distanceUnit: distanceUnit))
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                .foregroundStyle(active ? Theme.accent : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .background(active ? Theme.accent.opacity(0.16) : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? Theme.accent.opacity(0.55) : Theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("incrementChoice-\(metric.formatted(choice))")
    }
}
