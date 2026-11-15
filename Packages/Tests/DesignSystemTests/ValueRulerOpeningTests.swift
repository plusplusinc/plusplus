// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// Where a ruler rests as its row opens. The UIKit scroll view behind a ruler is made only when
/// it first draws, and it starts at the offset SwiftUI hands it then; a snapshot draws the
/// ruler fresh and open, so it cannot see one laid out shut beforehand.
@MainActor
@Suite("Value ruler opening in its row")
struct ValueRulerOpeningTests {
    @Observable
    final class Row {
        var width: CGFloat = 155
        var isOpen = false
    }

    private struct Shown: View {
        let row: Row
        var body: some View {
            ValueRow(
                label: "Weight",
                value: "25.0 lb",
                number: 25,
                spokenValue: "25 pounds",
                isOpen: row.isOpen,
                canDecrease: true,
                canIncrease: true,
                onToggle: { },
                onStep: { _ in },
                ruler: ValueRuler(value: 25, range: 5 ... 1000, onChange: { _ in }),
                accessory: EmptyView?.none,
                footer: EmptyView?.none,
            )
            .frame(width: row.width)
        }
    }

    @Test("A ruler laid out shut, narrow then wide, opens on its value", arguments: [
        UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge,
    ])
    func opensOnItsValue(at category: UIContentSizeCategory) throws {
        let row = Row()
        let host = UIHostingController(rootView: Shown(row: row))
        host.safeAreaRegions = []
        let window = UIWindow.sceneless(hosting: host, at: category)
        window.settle()
        row.width = 370
        window.settle()
        row.isOpen = true
        window.settle()
        let scroll = try #require(window.firstScrollView, "The open row has no ruler")
        let spacing = UIFontMetrics(forTextStyle: .subheadline)
            .scaledValue(for: ValueRuler.weightSpacing, compatibleWith: window.traitCollection)
        let scale = RulerScale(range: 5 ... 1000, tick: 0.5, spacing: spacing)
        #expect(scale.value(at: scroll.contentOffset.x) == 25)
    }
}

#endif
