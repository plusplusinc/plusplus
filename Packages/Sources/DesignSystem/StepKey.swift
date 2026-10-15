import SwiftUI

/// A stepper's key that steps once on a tap and, held, keeps stepping until it's let go: from
/// 0.3 s into the hold, about 12 steps a second, each with a light tap of haptic. It stops when
/// the finger lifts or slides off, when a scroll takes the touch, when the key can no longer be
/// used, and when it leaves the screen, and the lift that ends a hold doesn't add a step.
///
/// The hold follows the button's own pressed state rather than a long-press gesture laid on it,
/// which the button's tap kept from ever firing.
public struct StepKey: View {
    private let label: String
    private let onStep: () -> Void

    /// The hold, from the press until it's let go.
    @State private var hold: Task<Void, Never>?
    /// Set once a hold has repeated, so the tap its lift ends in doesn't step again.
    @State private var didRepeat = false
    /// Counts the steps a hold takes, for their haptic.
    @State private var ticks = 0
    @Environment(\.isEnabled) private var isEnabled
    @ObserveHotReload private var hotReload

    private static let threshold = Duration.seconds(0.3)
    private static let interval = Duration.seconds(1.0 / 12)

    public init(_ label: String, onStep: @escaping () -> Void) {
        self.label = label
        self.onStep = onStep
    }

    public var body: some View {
        Button {
            guard !didRepeat else {
                didRepeat = false
                return
            }
            onStep()
        } label: {
            Text(verbatim: label)
        }
        .buttonStyle(StepKeyButtonStyle { isPressed in
            if isPressed {
                startHold()
            } else {
                endHold()
            }
        })
        .sensoryFeedback(.impact(weight: .light, intensity: 0.55), trigger: ticks)
        .onChange(of: isEnabled) { _, isEnabled in
            if !isEnabled {
                endHold()
            }
        }
        .onDisappear(perform: endHold)
        .hotReloadable()
    }

    private func startHold() {
        endHold()
        didRepeat = false
        // A repeat's own clock, not a wait for something to settle.
        hold = Task {
            guard (try? await Task.sleep(for: Self.threshold)) != nil else { return }
            didRepeat = true
            while !Task.isCancelled {
                ticks += 1
                onStep()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    private func endHold() {
        hold?.cancel()
        hold = nil
    }
}

#Preview {
    @Previewable @State var value = 10
    VStack(spacing: Spacing.md) {
        NumberFieldContent(text: "\(value)", unit: nil, isEditing: false, blinks: false)
        HStack(spacing: Spacing.sm) {
            StepKey("\u{2212}1") { value -= 1 }
                .disabled(value <= 0)
            StepKey("+1") { value += 1 }
        }
    }
    .padding()
    .background(Color.pp(.surface))
}
