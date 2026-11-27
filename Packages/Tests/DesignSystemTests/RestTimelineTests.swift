// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// Every row of a workout holds a rest under its label and one above it (`LabelWithRest`), shut
/// but for the one resting. Shut, a rest draws nothing: no countdown's timeline, counted by
/// `RestBlock.countdownDraws`, which a hosted window's layout would otherwise draw once a row.
@MainActor
@Suite("Rest timelines")
struct RestTimelineTests {
    /// The countdown draws laying out `rows` in a window took.
    private func countdownDraws(laying rows: some View) -> Int {
        let before = RestBlock.countdownDraws
        let window = UIWindow.sceneless(hosting: UIHostingController(rootView: rows), at: .large)
        window.settle()
        return RestBlock.countdownDraws - before
    }

    @Test("Rows with their rests shut draw no countdown; a row resting draws its own")
    func shutRestsDrawNoCountdown() {
        let shut = VStack {
            ForEach(0 ..< 6) { row in
                LabelWithRest(label: Text(verbatim: "Squat \(row)"), rest: .closed)
            }
        }
        #expect(countdownDraws(laying: shut) == 0, "A shut rest drew its countdown")
        let resting = LabelWithRest(
            label: Text(verbatim: "Squat"),
            rest: RestBlock(stage: .open, length: 30, ends: .now.addingTimeInterval(30)),
        )
        #expect(countdownDraws(laying: resting) > 0, "The open rest drew no countdown")
    }
}

#endif
