// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing
import UIKit

/// With two offers on the line, a tap that takes the trailing one and a second tap on the same
/// spot take both: the offer left moves to the trailing edge, under the finger. Which offers a
/// text leaves is `FilterOfferTests`'; this is where the line puts the one left, read from the
/// hosted line as automation reads it, since a snapshot draws each line and compares none.
@MainActor
@Suite("Filter offer spot")
struct FilterOfferSpotTests {
    private func buttons(_ titles: [(String, String)]) throws -> [String: CGRect] {
        let line = FilterOfferLine(offers: titles.map { title, filter in
            .init(title: title, filterName: filter) { }
        })
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        var frames: [String: CGRect] = [:]
        for node in try AccessibilityTree.nodes(of: line) {
            // The button's own node; its word and its + are nodes under it.
            if let label = node.accessibilityLabel, label.hasPrefix("Add ") {
                frames[label] = node.accessibilityFrame
            }
        }
        return frames
    }

    @Test("The offer left after the trailing one is taken sits under the same tap")
    func offerLeftTakesTheSpot() throws {
        let both = try buttons([("Back", "Muscle"), ("Dumbbells", "Equipment")])
        let taken = try #require(both["Add dumbbells to Equipment"], "No Dumbbells offer")
        let tap = CGPoint(x: taken.midX, y: taken.midY)

        let left = try buttons([("Back", "Muscle")])
        let back = try #require(left["Add back to Muscle"], "No Back offer")
        #expect(back.contains(tap), "A tap at \(tap) misses Back at \(back)")
    }
}

#endif
