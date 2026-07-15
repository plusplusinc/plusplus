import SwiftUI
import PlusPlusKit

/// Rep-target wheels. Keyboard-free by design — the janky `.number`
/// TextFields died long ago; values are picked, never typed. (The v1
/// inline MetricRow/RepTargetRow pair that used to live here was
/// superseded by MetricStepperRow + the picker sheets and was deleted
/// as dead code in the 2026-07-15 scrubber pass.)

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
