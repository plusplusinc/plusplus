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
