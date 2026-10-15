import SwiftUI

/// A stepper's − and + keys, joined: two cells with a hairline between them and one outline
/// around both, as tall as it is given.
struct StepPair: View {
    let canDecrease: Bool
    let canIncrease: Bool
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    @ObserveHotReload private var hotReload

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sm)
        HStack(spacing: 0) {
            StepKey("Decrease", systemImage: "minus", onStep: onDecrease)
                .disabled(!canDecrease)
            Rectangle()
                .fill(.pp(.borderStrong))
                .frame(width: 1)
            StepKey("Increase", systemImage: "plus", onStep: onIncrease)
                .disabled(!canIncrease)
        }
        .fixedSize(horizontal: true, vertical: false)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.pp(.borderStrong)))
        .hotReloadable()
    }
}

/// A stepper's key that steps once on a tap and, held, keeps stepping until it's let go: from
/// 0.3 s into the hold, about 12 steps a second, each with a light tap of haptic. It stops when
/// the finger lifts or slides off, when a scroll takes the touch, when the key can no longer be
/// used, and when it leaves the screen, and the lift that ends a hold doesn't add a step.
///
/// The hold follows the button's own pressed state rather than a long-press gesture laid on it,
/// which the button's tap kept from ever firing.
struct StepKey: View {
    private let title: String
    private let systemImage: String
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

    init(_ title: String, systemImage: String, onStep: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.onStep = onStep
    }

    var body: some View {
        Button(title, systemImage: systemImage) {
            guard !didRepeat else {
                didRepeat = false
                return
            }
            onStep()
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
    HStack(spacing: Spacing.sm) {
        NumberFieldContent(
            text: "\(value)",
            amount: Double(value),
            unit: nil,
            isEditing: false,
            blinks: false,
        )
        StepPair(
            canDecrease: value > 0,
            canIncrease: true,
            onDecrease: { value -= 1 },
            onIncrease: { value += 1 },
        )
    }
    .frame(height: 44)
    .padding()
    .background(Color.pp(.surface))
}
