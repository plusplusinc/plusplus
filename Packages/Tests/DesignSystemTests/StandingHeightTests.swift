// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing
import UIKit

/// The current exercise takes its height in the layout pass that first places it: what the
/// screen gives it and the row after it, measured in that pass. Read back from the screen and the
/// next row after layout, the height came a pass later, and on a relaunch into a workout the row
/// grew in the same frame it was first laid out in, which SwiftUI logs as a fault.
@MainActor
@Suite("The current exercise stands at its height in one pass")
struct StandingHeightTests {
    private nonisolated static let large = UIContentSizeCategory.large
    private nonisolated static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge

    /// Every size each row was laid out at, the screen's height, and every content height the
    /// scroll view reported.
    private final class Log {
        var rows: [Int: [CGSize]] = [:]
        var screen: CGFloat = 0
        var contentHeights: [CGFloat] = []
    }

    private struct Row: Identifiable {
        let id: Int
        let title: String
        let detail: [String]
    }

    private struct Host: View {
        let log: Log
        let rows = [
            Row(id: 0, title: "Dumbbell bench press", detail: ["3 × 10 reps", "20 kg"]),
            Row(id: 1, title: "Band external rotation", detail: ["2 × 15 reps per side"]),
        ]

        var body: some View {
            GeometryReader { screen in
                let standing = RowStanding(
                    height: screen.size.height,
                    next: .init(title: rows[1].title, detail: rows[1].detail),
                )
                ScrollView {
                    Rail(rows, current: 0) { row in
                        RowLabel(
                            title: row.title,
                            detail: row.detail,
                            focus: row.id == 0 ? RowFocus(
                                progress: "Set 1 of 3",
                                figures: [.init(number: "10", unit: "reps")],
                                spokenFigures: "10 reps",
                            ) : nil,
                            standing: row.id == 0 ? standing : nil,
                        )
                        .railRow()
                        .onGeometryChange(for: CGSize.self, of: \.size) {
                            log.rows[row.id, default: []].append($0)
                        }
                    } end: {
                        EmptyView()
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self, of: \.contentSize.height) { _, height in
                    log.contentHeights.append(height)
                }
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { log.screen = $0 }
            }
        }
    }

    @Test("The current exercise and the row after it fill the screen, laid out once", arguments: [
        large,
        ax5,
    ])
    func laidOutOnce(category: UIContentSizeCategory) throws {
        let log = Log()
        let host = UIHostingController(rootView: Host(log: log))
        let window = UIWindow.sceneless(hosting: host, at: category)
        defer { window.isHidden = true }
        window.settle()
        let current = try #require(log.rows[0])
        let next = try #require(log.rows[1]?.last)
        #expect(current.count == 1, "\(category.rawValue): laid out at \(current)")
        // The label stands as tall as the screen leaves it, and the row adds its insets.
        let insets = RailRowMetrics.verticalInset * 2
        let filled = try #require(current.last).height + next.height
        #expect(
            abs(filled - (log.screen + insets)) < 0.5,
            "\(category.rawValue): rows \(filled) on a screen \(log.screen)",
        )
        // Whether the scroll view reports its first value is its own business; a second, different
        // one is the current exercise growing after it was placed.
        #expect(
            Set(log.contentHeights).count <= 1,
            "\(category.rawValue): content heights \(log.contentHeights)",
        )
    }
}

#endif
