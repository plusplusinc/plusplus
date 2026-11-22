// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// A row's swipe actions are built again only when what they show or act on changes. Built again
/// on every run of the body holding them, as `swipeActions` written in place are, they reached
/// the swipe container twice in the frame a screen's rows were first laid out in, when the
/// screen took a size it had measured there, which SwiftUI logs as a fault. The fault never shows
/// in a hosted window, so the builds are counted.
@MainActor
@Suite("Row swipes")
struct RowSwipeTests {
    final class Log {
        var builds = 0
        var hostRuns = 0
        var removed: Int?
    }

    /// A row whose screen takes a width it measures in the row's first layout, as the rail takes
    /// its column's. Its swipe acts on 1, or, given `measuredValue`, on that once measured.
    private struct Host: View {
        let log: Log
        let measuredValue: Int?
        @State private var width: CGFloat = 0

        var body: some View {
            log.hostRuns += 1
            return ScrollView {
                Text(width > 0 ? "Measured" : "Unmeasured")
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
                    .modifier(RowSwipe(
                        title: "Remove",
                        value: width > 0 ? measuredValue ?? 1 : 1,
                        // A new closure on every run, as the screens' are.
                        action: { log.removed = $0 },
                        onBuild: { log.builds += 1 },
                    ))
            }
            .swipeActionsContainer()
        }
    }

    /// How many times the row's swipe actions were built as the host settled. The first row
    /// swipe hosted in a test process was built on every run of its host, with or without
    /// `RowSwipe`'s `Equatable` conformance, and every one after it once, so one is hosted first
    /// and not counted.
    private func builds(measuredValue: Int? = nil) throws -> Int {
        var counts: [Int] = []
        for _ in 0 ..< 2 {
            let log = Log()
            let window = UIWindow.sceneless(
                hosting: UIHostingController(rootView: Host(
                    log: log,
                    measuredValue: measuredValue,
                )),
                at: .large,
            )
            window.settle()
            window.isHidden = true
            try #require(log.hostRuns > 1, "The measured width never ran the screen's body again")
            counts.append(log.builds)
        }
        return counts[1]
    }

    @Test("A screen's body running again over the same row leaves its swipe actions as built")
    func builtOnceForTheSameValue() throws {
        let count = try builds()
        #expect(count == 1)
    }

    @Test("A row's swipe actions are built again for a new value")
    func builtAgainForANewValue() throws {
        let count = try builds(measuredValue: 2)
        #expect(count == 2)
    }
}

#endif
