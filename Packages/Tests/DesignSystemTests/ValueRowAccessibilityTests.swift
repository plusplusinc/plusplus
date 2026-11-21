// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// What VoiceOver reads for a value row with a tag: the row is one element, and its value says
/// the tag only while the tag shows. Hidden, the tag keeps its room, so it is still laid out;
/// read as part of the value then, VoiceOver would call a rest set by hand automatic.
@MainActor
@Suite("Value row's accessibility")
struct ValueRowAccessibilityTests {
    @Test("A row's value says its tag while the tag shows, and not once it hides")
    func tagSpokenOnlyWhileShown() throws {
        #expect(try spokenValue(showsTag: true) == "1 minute, 30 seconds, Auto")
        #expect(try spokenValue(showsTag: false) == "1 minute, 30 seconds")
    }

    /// Whether the ruler's labels reach the tree shows only in the running app, where its
    /// UIKit scroll view exists (`WorkoutDrawerUITests`); hosted, they never did.
    @Test("An open ruler row is one adjustable element that steps up and down")
    func openRulerRowSteps() throws {
        var steps: [Int] = []
        let row = ValueRow(
            label: "Weight",
            value: "25.0 lb",
            number: 25,
            spokenValue: "25 pounds",
            isOpen: true,
            canDecrease: true,
            canIncrease: true,
            onToggle: { },
            onStep: { steps.append($0) },
            ruler: ValueRuler(value: 25, range: 5 ... 1000, onChange: { _ in }),
            accessory: EmptyView?.none,
            footer: EmptyView?.none,
        )
        let nodes = try AccessibilityTree.nodes(of: row.frame(width: 402))
        let element = try #require(nodes.first { $0.accessibilityLabel == "Weight" })
        #expect(element.accessibilityTraits.contains(.adjustable))
        element.accessibilityIncrement()
        element.accessibilityDecrement()
        #expect(steps == [1, -1])
    }

    /// The value of the element VoiceOver reads for a Rest row, tagged Auto.
    private func spokenValue(showsTag: Bool) throws -> String? {
        let row = ValueRow(
            label: "Rest",
            note: "After each set",
            value: "1m\u{00A0}30s",
            tag: "Auto",
            showsTag: showsTag,
            spokenValue: "1 minute, 30 seconds",
            isOpen: false,
            canDecrease: true,
            canIncrease: true,
            onToggle: { },
            onStep: { _ in },
        )
        let nodes = try AccessibilityTree.nodes(of: row.frame(width: 402))
        let element = try #require(
            nodes.first { $0.accessibilityLabel?.hasPrefix("Rest") == true },
            "No element labeled Rest in \(nodes.compactMap(\.accessibilityLabel))",
        )
        return element.accessibilityValue
    }
}

#endif
