import SwiftUI

/// How far a list is scrolled and its scroll phase, which the list reports, and a scroll in a
/// sequence that the next beat waits for. An animated scroll's `withAnimation` completion runs at
/// once, as the scroll is not a SwiftUI animation, so the beat waits for the scroll to stop: the
/// first idle phase reported. Not before: a scroll set while the spring still settles around its
/// end, a point or two either side of it, is undone by it. Not observed: nothing is drawn from it.
public final class ScrollBeat {
    /// How far the list is scrolled.
    public private(set) var scrolledY: CGFloat = 0
    /// The list's scroll phase.
    public private(set) var phase = ScrollPhase.idle
    /// The beat waiting for the scroll to stop, and what gives it up.
    private var waiting: CheckedContinuation<Void, Never>?
    private var giveUp: Task<Void, Never>?

    public init() { }

    /// Whether the list is pulled down past its top, rubber-banding.
    public var isPastTop: Bool {
        scrolledY < 0
    }

    /// Whether a finger is on the list, scrolling it or about to.
    public var isFingerOn: Bool {
        phase == .interacting || phase == .tracking
    }

    /// Whether the list is at its top, so there is nothing to scroll.
    public var isListAtTop: Bool {
        scrolledY < 0.5
    }

    /// Scrolls with `scroll`, then returns once the list reports it has stopped, or once
    /// `giveUp` returns, whichever is first, or at once if the task is cancelled: a scroll that
    /// never reports stopping does not hold the sequence forever.
    public func settled(
        after scroll: () -> Void,
        orWhen giveUp: @escaping @MainActor () async -> Void,
    ) async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                finishWaiting()
                waiting = continuation
                scroll()
                self.giveUp = Task {
                    await giveUp()
                    // Cancelled, this wait has already ended, and another may have begun.
                    if !Task.isCancelled {
                        finishWaiting()
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in self.finishWaiting() }
        }
    }

    /// Whether the list rests on `y` or is on its way there: `position` was last scrolled to `y`,
    /// or, scrolled by a finger or to an edge, the list reports `y`. A scroll asked for is
    /// reported a frame or more later, after the next layout may have moved what it was aimed at.
    public func rests(on y: CGFloat, asked position: ScrollPosition) -> Bool {
        // A finger's scroll also clears `y` (iOS 27.2); the documented flag doesn't rely on it.
        let asked = position.isPositionedByUser ? nil : position.y
        return abs((asked ?? scrolledY) - y) < 1
    }

    public func listMoved(to scrolledY: CGFloat) {
        self.scrolledY = scrolledY
    }

    public func phaseChanged(to phase: ScrollPhase) {
        self.phase = phase
        if phase == .idle {
            finishWaiting()
        }
    }

    private func finishWaiting() {
        giveUp?.cancel()
        giveUp = nil
        waiting?.resume()
        waiting = nil
    }
}
