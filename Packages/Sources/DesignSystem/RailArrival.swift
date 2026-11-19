import SwiftUI

/// An added row's beats onto its rail, each a deadline timed from its own start: the append,
/// then the wait for the list's end to come into view, then the entry, then the time the
/// entry takes to land. Never an animation's completion: an append's completion once never came
/// (Xcode Cloud run 454), and the row stayed arriving, drawn empty and out of the accessibility
/// tree, for good. The wait for the end is given up at a deadline too, so no path leaves a row
/// arriving.
public enum RailArrival {
    /// The append's fade, of a row that draws nothing yet, which starts the wait for the list's
    /// end a moment into the picker's slide.
    public static let appendFade: TimeInterval = 0.1
    /// From the add to the wait for the list's end: the append's fade and the frames its
    /// completion took to come behind the picker's dismissal, which once timed the entry where
    /// the end is in view (measured 0.37 to 0.41 s from the sheet's slide to the node). The
    /// routine screen's `reachEnd` holds the entry a pause longer.
    static let appended: Duration = .milliseconds(180)
    /// From the row being let go to its node and content having landed (`RailEntry`): until
    /// then it takes no taps and VoiceOver does not reach it.
    static let entry: Duration = .seconds(RailEntry.popStart(reduceMotion: false) + RailEntry.pop)
    /// How long the wait for the list's end may take before the row enters anyway, where it is.
    public static let endGiveUp: Duration = .seconds(1.25)
}

extension RailArrival {
    /// Plays an added row's beats. `isArriving` says whether the row is still the one arriving,
    /// as a later add takes its place; `reachEnd` returns once the list's end is in view, at
    /// once if it already is; `enter` lets the row go onto the rail; `entered` runs once it has
    /// landed.
    public static func play(
        givingUpAfter giveUp: Duration = endGiveUp,
        isArriving: () -> Bool,
        reachEnd: @escaping @MainActor () async -> Void,
        enter: () -> Void,
        entered: () -> Void,
    ) async {
        try? await Task.sleep(for: appended, tolerance: .zero)
        guard isArriving() else { return }
        await withTaskGroup { group in
            group.addTask { await reachEnd() }
            group.addTask { try? await Task.sleep(for: giveUp, tolerance: .zero) }
            await group.next()
            group.cancelAll()
        }
        guard isArriving() else { return }
        enter()
        try? await Task.sleep(for: entry, tolerance: .zero)
        entered()
    }
}
