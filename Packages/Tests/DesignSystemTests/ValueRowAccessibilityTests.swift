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
        #expect(try spokenValue(showsTag: true) == "90 seconds, Auto")
        #expect(try spokenValue(showsTag: false) == "90 seconds")
    }

    /// The value of the element VoiceOver reads for a Rest row, tagged Auto.
    private func spokenValue(showsTag: Bool) throws -> String? {
        let row = ValueRow(
            label: "Rest",
            note: "After each set",
            value: "90\u{00A0}s",
            tag: "Auto",
            showsTag: showsTag,
            spokenValue: "90 seconds",
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
