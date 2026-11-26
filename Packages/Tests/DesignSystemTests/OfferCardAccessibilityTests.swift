// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// What VoiceOver reads for an offer card, as Log's Apple Health card: its title as a heading,
/// then its two buttons, each named for what it does and big enough to hit. The snapshot
/// (`OfferCardSnapshotTests`) holds its look, which says nothing of traits or of a target's
/// size around the plain "Not now".
@MainActor
@Suite("Offer card's accessibility")
struct OfferCardAccessibilityTests {
    @Test("The title is a heading, and the offer and the way out are buttons, read in that order")
    func headingThenTwoButtons() throws {
        let nodes = try AccessibilityTree.nodes(of: card().frame(width: 402))
        let title = try #require(
            nodes.first { $0.accessibilityLabel == "Save your workouts to Apple Health" },
            "No element for the title in \(nodes.compactMap(\.accessibilityLabel))",
        )
        #expect(title.accessibilityTraits.contains(.header))
        let buttons = nodes.filter { $0.accessibilityTraits.contains(.button) }
        #expect(buttons.map(\.accessibilityLabel) == ["Save to Apple Health", "Not now"])
        let read = nodes.compactMap(\.accessibilityLabel)
        let titleAt = try #require(read.firstIndex(of: "Save your workouts to Apple Health"))
        let offerAt = try #require(read.firstIndex(of: "Save to Apple Health"))
        #expect(titleAt < offerAt)
    }

    @Test("Each button is a target at least 44 points wide and tall")
    func targetsAreBigEnough() throws {
        let buttons = try AccessibilityTree.nodes(of: card().frame(width: 402))
            .filter { $0.accessibilityTraits.contains(.button) }
        #expect(buttons.count == 2)
        for button in buttons {
            // To a hundredth: the frame comes back through a transform, a hair under.
            let width = (button.accessibilityFrame.width * 100).rounded() / 100
            let height = (button.accessibilityFrame.height * 100).rounded() / 100
            let name = button.accessibilityLabel ?? "?"
            #expect(width >= 44, "\(name) is \(width) points wide")
            #expect(height >= 44, "\(name) is \(height) points tall")
        }
    }

    private func card() -> OfferCard {
        OfferCard(
            "Save your workouts to Apple Health",
            line: "Each workout you finish, with its type and how long it took.",
            offer: "Save to Apple Health",
            dismiss: "Not now",
            take: { },
            decline: { },
        )
    }
}

#endif
