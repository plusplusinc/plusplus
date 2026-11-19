import SwiftUI

/// The current exercise's pulse: its green dims and comes back, slowly, over and over. One
/// clock, the time itself, drives every view that pulses, the node and the current set's bar, so
/// they dim and brighten together and never drift apart. With Reduce Motion it holds steady.
nonisolated enum CurrentPulse {
    /// One dim and back, in seconds.
    static let period = 1.8
    /// How much of the background is laid over the green at the dimmest.
    static let deepest = 0.45

    /// How dim the green is at `date`: 0 at full green, `deepest` at the dimmest, on a sine, so
    /// it eases in and out at each end.
    static func dim(at date: Date) -> Double {
        dim(phase: date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period)
    }

    /// How dim the green is a share `phase` of the way through one dim and back, from full green
    /// at 0 and 1. A rest's dot runs it once a second, full green as the countdown turns.
    static func dim(phase: Double) -> Double {
        deepest * (1 - cos(2 * .pi * phase)) / 2
    }
}

extension EnvironmentValues {
    /// Holds the pulse at full green, so a snapshot or a preview draws it at rest.
    @Entry var isPulseHeld = false
    /// A rest between two sets of the current exercise, whose beat the pulse takes on.
    @Entry public var restBeat: RestBeat?
}

/// A rest between two sets, on whose countdown the current exercise's pulse beats once a second,
/// full green as each figure turns, as the rest's dot does between exercises. It blends in from
/// the slow pulse over `blend` from the log, and back to it over `blend` after the end.
public nonisolated struct RestBeat: Equatable, Sendable {
    let starts: Date
    let ends: Date
    /// While paused, the seconds left; nil while running.
    let pausedLeft: Double?

    public init(starts: Date, ends: Date, pausedLeft: Double?) {
        self.starts = starts
        self.ends = ends
        self.pausedLeft = pausedLeft
    }

    static let blend = 1.0

    func dim(at date: Date) -> Double {
        let node = CurrentPulse.dim(at: date)
        let left = pausedLeft ?? ends.timeIntervalSince(date)
        let beat = left > 0 ? CurrentPulse.dim(phase: left.rounded(.up) - left) : 0
        let into = min(max(date.timeIntervalSince(starts) / Self.blend, 0), 1)
        let out = pausedLeft == nil
            ? min(max(date.timeIntervalSince(ends) / Self.blend, 0), 1) : 0
        let weight = into * (1 - out)
        return node * (1 - weight) + beat * weight
    }
}

extension View {
    /// Pulses this view's green within `shape`, on the one clock every pulse shares, dimmed by
    /// `share` of the pulse's dimming: less than 1 where it hands over to or from the rest's dot,
    /// which holds its green full.
    func currentPulse(in shape: some Shape, share: Double = 1) -> some View {
        modifier(CurrentPulseOverlay(shape: shape, share: share))
    }
}

private struct CurrentPulseOverlay<S: Shape>: ViewModifier {
    let shape: S
    let share: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isPulseHeld) private var isHeld
    @Environment(\.restBeat) private var restBeat

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion, !isHeld, share > 0 {
                // A slow sine in brightness: 30 frames a second draw it smoothly, at a quarter of a
                // ProMotion screen's rate, through a workout that keeps the screen on.
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    shape
                        .fill(.pp(.background))
                        .opacity((restBeat?.dim(at: context.date)
                                ?? CurrentPulse.dim(at: context.date)) * share)
                }
                .allowsHitTesting(false)
            }
        }
    }
}
