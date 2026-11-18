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
    /// Where the list last reported reaching a scroll asked for. A scroll asked for there again,
    /// as a landing asked for each layout pass is, has already been reached.
    private var reachedY: CGFloat?

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

    /// Whether the list rests on `y` or is on its way there: `position` was last scrolled to `y`
    /// and the list has not yet reported getting there, or the list reports `y`. A scroll asked
    /// for is reported a frame or more later, after the next layout may have moved what it was
    /// aimed at. Once reported, only the report counts: a scroll the app did not ask for, such as
    /// a status-bar tap's to the top, leaves `position` where it was and reports no phase.
    public func rests(on y: CGFloat, asked position: ScrollPosition) -> Bool {
        // A finger's scroll also clears `y` (iOS 27.2); the documented flag doesn't rely on it.
        guard !position.isPositionedByUser, let asked = position.y,
              reachedY.map({ abs($0 - asked) >= 1 }) ?? true
        else {
            return abs(scrolledY - y) < 1
        }
        return abs(asked - y) < 1
    }

    /// `position` is the scroll last asked for, which the list may have just reached.
    public func listMoved(to scrolledY: CGFloat, asked position: ScrollPosition) {
        self.scrolledY = scrolledY
        if let y = position.y, abs(scrolledY - y) < 1 {
            reachedY = y
        }
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
