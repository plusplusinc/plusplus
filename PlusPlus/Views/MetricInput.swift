import SwiftUI

/// The editable quantities on a WorkoutExercise. Pure value logic —
/// stepping, clamping, wheel values, display formatting — lives here so it
/// can be unit tested without a view or a ModelContainer.
enum WorkoutMetric {
    case weight
    case reps
    case duration

    var label: String {
        switch self {
        case .weight: "Weight"
        case .reps: "Reps"
        case .duration: "Duration"
        }
    }

    var unit: String {
        switch self {
        case .weight: "lb"
        case .reps: "reps"
        case .duration: "sec"
        }
    }

    /// Increment applied by the stepper's plus/minus buttons.
    var step: Double {
        switch self {
        case .weight: 5
        case .reps: 1
        case .duration: 15
        }
    }

    /// Granularity of the wheel picker — finer than the stepper for weight
    /// so microplate loads (2.5 lb) stay reachable.
    var wheelStep: Double {
        switch self {
        case .weight: 2.5
        case .reps: 1
        case .duration: 5
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .weight: 0...1000
        case .reps: 1...100
        case .duration: 5...900
        }
    }

    /// Starting point when a value is first set from empty.
    var defaultValue: Double {
        switch self {
        case .weight: 45
        case .reps: 10
        case .duration: 30
        }
    }

    func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Stepping from nil lands on `defaultValue` rather than stepping from zero.
    func incremented(_ value: Double?) -> Double {
        guard let value else { return defaultValue }
        return clamped(value + step)
    }

    func decremented(_ value: Double?) -> Double {
        guard let value else { return defaultValue }
        return clamped(value - step)
    }

    var wheelValues: [Double] {
        Array(stride(from: range.lowerBound, through: range.upperBound, by: wheelStep))
    }

    /// Snaps an arbitrary stored value onto the wheel so the picker has a
    /// valid selection; nil lands on `defaultValue`.
    func nearestWheelValue(to value: Double?) -> Double {
        guard let value else { return defaultValue }
        let bounded = clamped(value)
        let steps = ((bounded - range.lowerBound) / wheelStep).rounded()
        return range.lowerBound + steps * wheelStep
    }

    /// Whole numbers render without a decimal; fractional weights keep one place.
    func formatted(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

/// A single metric line: label, tappable value that opens a wheel picker for
/// large jumps, and a stepper for fine adjustment. Keyboard-free by design —
/// replaces the janky `.number` TextFields.
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
