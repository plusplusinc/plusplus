import SwiftUI

/// The current exercise's pulse: its green dims and comes back, slowly, over and over. One
/// clock, the time itself, drives every view that pulses, the node and the current set's bar, so
/// they dim and brighten together and never drift apart. With Reduce Motion it holds steady.
enum CurrentPulse {
    /// One dim and back, in seconds.
    static let period = 1.8
    /// How much of the background is laid over the green at the dimmest.
    static let deepest = 0.45

    /// How dim the green is at `date`: 0 at full green, `deepest` at the dimmest, on a sine, so
    /// it eases in and out at each end.
    static func dim(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period
        return deepest * (1 - cos(2 * .pi * phase)) / 2
    }
}

extension EnvironmentValues {
    /// Holds the pulse at full green, so a snapshot or a preview draws it at rest.
    @Entry var isPulseHeld = false
}

extension View {
    /// Pulses this view's green within `shape`, on the one clock every pulse shares.
    func currentPulse(in shape: some Shape) -> some View {
        modifier(CurrentPulseOverlay(shape: shape))
    }
}

private struct CurrentPulseOverlay<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isPulseHeld) private var isHeld

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion, !isHeld {
                TimelineView(.animation) { context in
                    shape
                        .fill(.pp(.background))
                        .opacity(CurrentPulse.dim(at: context.date))
                }
                .allowsHitTesting(false)
            }
        }
    }
}
