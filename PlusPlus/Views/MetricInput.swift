import SwiftUI

/// A single metric line: label, tappable value that opens a wheel picker for
/// large jumps, and a stepper for fine adjustment. Keyboard-free by design —
/// replaces the janky `.number` TextFields. Value semantics live in
/// `WorkoutMetric` (separate file, no SwiftUI dependency).
struct MetricRow: View {
    let metric: WorkoutMetric
    @Binding var value: Double?

    @State private var showingWheel = false

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
                    Text(metric.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)

            Stepper(metric.label) {
                value = metric.incremented(value)
            } onDecrement: {
                value = metric.decremented(value)
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
                get: { metric.nearestWheelValue(to: value) },
                set: { value = $0 }
            )) {
                ForEach(metric.wheelValues, id: \.self) { candidate in
                    Text("\(metric.formatted(candidate)) \(metric.unit)")
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
private struct RepTargetWheelSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (RepTarget) -> Void

    @State private var wheelLower: Int
    @State private var wheelUpper: Int?

    init(target: RepTarget, onSave: @escaping (RepTarget) -> Void) {
        self.onSave = onSave
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
