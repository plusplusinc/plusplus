// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// What VoiceOver reads for a rest: while it runs, one element, "Rest", whose value is the time
/// left in words, and two buttons at the bottom named for what they do. A row keeps the room for
/// a rest it isn't running, laid out and unseen; read, every row would say "Rest, 0 seconds".
/// That room's node stays in the tree automation reads (`axe describe-ui` lists it), marked
/// hidden, so what is checked is what VoiceOver stops on: an element that is not hidden.
@MainActor
@Suite("Rest's accessibility")
struct RestAccessibilityTests {
    @Test("A running rest is one element, Rest, its value the time left in words")
    func runningRestReadsItsTimeLeft() throws {
        let rest = RestBlock(stage: .open, length: 90, pausedLeft: 35)
        #expect(try spokenRests(in: rest) == ["35 seconds"])
    }

    @Test("A rest that isn't running is nothing VoiceOver reads")
    func closedRestIsNotRead() throws {
        #expect(try spokenRests(in: RestBlock.closed) == [])
    }

    /// The value of each element labeled "Rest" that VoiceOver stops on in `view`, at a phone's
    /// width.
    private func spokenRests(in view: some View) throws -> [String?] {
        try AccessibilityTree.nodes(of: view.frame(width: 402))
            .filter { $0.accessibilityLabel == "Rest" }
            .filter { $0.isAccessibilityElement && !$0.accessibilityElementsHidden }
            .map(\.accessibilityValue)
    }
}

#endif
