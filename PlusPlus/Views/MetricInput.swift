import SwiftUI
import PlusPlusKit

/// A single metric line: label, tappable value that opens a wheel picker for
/// large jumps, and a stepper for fine adjustment. Keyboard-free by design —
/// replaces the janky `.number` TextFields. Value semantics live in
/// `WorkoutMetric` (separate file, no SwiftUI dependency).
struct MetricRow: View {
    let metric: WorkoutMetric
    @Binding var value: Double?

    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    @State private var showingWheel = false

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .lb
    }

    var body: some View {
        HStack {
            Text(metric.label)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                showingWheel = true
            } label: {
                HStack(spacing: 4) {
                    Text(metric.formatted(value))
                        .font(.body.monospacedDigit())
                        .fontWeight(.medium)
                        // Rolling digits on step, directional (#216).
                        .contentTransition(.numericText(value: value ?? 0))
                        .animation(Theme.Anim.standard, value: value)
                    let unit = metric.unit(for: value, weightUnit: weightUnit)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(metric.label)
            .accessibilityValue(metric.formatted(value))
            .accessibilityHint("Opens a picker")

            Stepper(metric.label) {
                value = metric.incremented(value, weightUnit: weightUnit)
            } onDecrement: {
                value = metric.decremented(value, weightUnit: weightUnit)
            }
            .labelsHidden()
        }
        .sheet(isPresented: $showingWheel) {
            wheelPicker
        }
    }

    private var wheelPicker: some View {
        NavigationStack {
            Picker(metric.label, selection: Binding(
                get: { metric.nearestWheelValue(to: value, weightUnit: weightUnit) },
                set: { value = $0 }
            )) {
                ForEach(metric.wheelValues(weightUnit: weightUnit), id: \.self) { candidate in
                    Text(metric.displayText(candidate, weightUnit: weightUnit))
                        .tag(candidate)
                }
            }
            .pickerStyle(.wheel)
            .navigationTitle(metric.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingWheel = false }
                }
            }
        }
        .presentationDetents([.height(280)])
    }
}

/// Rep-target line supporting ranges ("15–20 reps"). Same interaction
/// grammar as MetricRow: tap the value for wheels, stepper to shift.
struct RepTargetRow: View {
    @Binding var lower: Int?
    @Binding var upper: Int?

    @State private var showingWheel = false

    private var target: RepTarget {
        RepTarget(lower: lower, upper: upper)
    }

    private func setTarget(_ newTarget: RepTarget) {
        lower = newTarget.lower
        upper = newTarget.upper
    }

    var body: some View {
        HStack {
            Text("Reps")
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                showingWheel = true
            } label: {
                HStack(spacing: 4) {
                    Text(target.display)
                        .font(.body.monospacedDigit())
                        .fontWeight(.medium)
                        // Ranges shift whole ("15–20" → "16–21"), so the
                        // lower bound carries the roll direction (#216).
                        .contentTransition(.numericText(value: Double(lower ?? 0)))
                        .animation(Theme.Anim.standard, value: target.display)
                    Text("reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)

            Stepper("Reps") {
                setTarget(target.incremented())
            } onDecrement: {
                setTarget(target.decremented())
            }
            .labelsHidden()
        }
        .sheet(isPresented: $showingWheel) {
            RepTargetWheelSheet(target: target) { newTarget in
                setTarget(newTarget)
            }
        }
    }
}

/// Two wheels: the target (or range start) and an optional "up to" bound.
struct RepTargetWheelSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (RepTarget) -> Void
    /// Logging contexts pass false (#246): an actual rep count is a
    /// scalar, and the range editor's "Up to" wheel was silently
    /// discarded there — a dead control during the user's first log.
    var showsUpperWheel = true

    @State private var wheelLower: Int
    @State private var wheelUpper: Int?

    init(target: RepTarget, showsUpperWheel: Bool = true, onSave: @escaping (RepTarget) -> Void) {
        self.onSave = onSave
        self.showsUpperWheel = showsUpperWheel
        _wheelLower = State(initialValue: target.lower ?? RepTarget.defaultReps)
        _wheelUpper = State(initialValue: target.upper)
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                VStack {
                    Text("Reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Reps", selection: $wheelLower) {
                        ForEach(RepTarget.allowedReps, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                }

                if showsUpperWheel {
                    VStack {
                        Text("Up to")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Up to", selection: $wheelUpper) {
                            Text("—").tag(Int?.none)
                            ForEach(RepTarget.allowedReps, id: \.self) { value in
                                Text("\(value)").tag(Int?.some(value))
                            }
                        }
                        .pickerStyle(.wheel)
                    }
                }
            }
            .padding(.horizontal)
            .navigationTitle("Reps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(RepTarget(lower: wheelLower, upper: wheelUpper))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(320)])
    }
}

/// Bridges optional Int model storage (reps, durations) to MetricRow's
/// Double-based interface. Shared by the detail and execution screens.
func intMetricBinding(_ source: Binding<Int?>) -> Binding<Double?> {
    Binding(
        get: { source.wrappedValue.map(Double.init) },
        set: { source.wrappedValue = $0.map { Int($0.rounded()) } }
    )
}
