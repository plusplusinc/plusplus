import DesignSystem
import SwiftUI

/// A stepper key that steps once on a tap and, held, keeps stepping until it's let go: from
/// 0.3 s into the hold, about 12 steps a second. The system's `buttonRepeatBehavior` waits
/// longer before it repeats, and its wait can't be set. The hold stops when the finger lifts or
/// slides off, when a scroll takes the touch, and when the key leaves the screen, and the lift
/// that ends a hold doesn't add a step.
///
/// The hold follows the button's own pressed state, since a long-press gesture laid on a button
/// never fires: the button's tap wins.
struct StepKey<Label: View>: View {
    private let onStep: () -> Void
    private let label: Label

    /// The hold, from the press until it's let go.
    @State private var hold: Task<Void, Never>?
    /// Set once a hold has repeated, so the tap its lift ends in doesn't step again.
    @State private var didRepeat = false
    @ObserveHotReload private var hotReload

    private static var threshold: Duration { .seconds(0.3) }
    private static var interval: Duration { .seconds(1.0 / 12) }

    init(onStep: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.onStep = onStep
        self.label = label()
    }

    var body: some View {
        Button {
            guard !didRepeat else {
                didRepeat = false
                return
            }
            onStep()
        } label: {
            label
        }
        .buttonStyle(PressReporting { isPressed in
            if isPressed {
                startHold()
            } else {
                endHold()
            }
        })
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

/// Draws the label as the plain style does, dimmed while pressed, and reports each change of
/// its pressed state.
private struct PressReporting: ButtonStyle {
    let onPress: (Bool) -> Void
    @ObserveHotReload private var hotReload

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPress(isPressed)
            }
            .hotReloadable()
    }
}
