// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// The primary key's bar measures the screen's bottom safe area for its sides, which it learns
/// only after its first layout. If the bar's height followed that measurement, the bar would
/// change the list's inset in the frame after the list was first laid out, and SwiftUI updated
/// the list's scroll geometry twice in one frame, which it logs as an `OnScrollGeometryChange`
/// fault at every launch. The fault doesn't show in a hosted view, so this watches its cause:
/// the room the bar takes from the list, which has to be the same from the first layout on.
@MainActor
@Suite("Primary key bar")
struct PrimaryKeyBarTests {
    /// The list's bottom safe area at each layout that changed it.
    private final class Insets {
        var seen: [CGFloat] = []
    }

    private struct Host: View {
        let insets: Insets

        var body: some View {
            ScrollView {
                Color.clear.frame(height: 2000)
            }
            .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.bottom) {
                insets.seen.append($0)
            }
            .primaryKeyBar(isPresented: true) {
                Button("Start") { }
            }
        }
    }

    /// In a window with a home indicator's safe area below, as the sceneless one has.
    @Test("The bar takes the same room from the list from its first layout")
    func roomHoldsFromFirstLayout() throws {
        let insets = Insets()
        let host = UIHostingController(rootView: Host(insets: insets))
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.settle()
        let first = try #require(insets.seen.first, "the list was never laid out")
        #expect(first > window.safeAreaInsets.bottom, "the bar took no room from the list")
        #expect(insets.seen == [first], "the bar's room changed after its first layout")
    }

    /// The +1 that pops off the key is only seen. Marked `accessibilityHidden`, it still stood in
    /// the tree as a "+1" text over the key between bursts, at opacity 0, where automation and
    /// `axe describe-ui` read it. The key, a plain button, is the bar's only node.
    @Test("At rest, the key's +1 puts nothing in the accessibility tree")
    func plusOneLeavesNoNodeAtRest() throws {
        let leaves = try AccessibilityTree.leaves(
            of: Text(verbatim: "Bench press").frame(maxHeight: .infinity)
                .primaryKeyBar(isPresented: true, plusOnes: 3) { Button("Log set") { } },
        )
        let labels = leaves.map { $0.accessibilityLabel ?? "unlabeled at \($0.accessibilityFrame)" }
        #expect(labels == ["Bench press", "Log set"])
    }
}

#endif
