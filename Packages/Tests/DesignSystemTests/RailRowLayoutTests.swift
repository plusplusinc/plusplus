// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing
import UIKit

/// A rail row takes its size in the layout pass that first places it. A row that measured itself
/// and then narrowed its text grew taller a pass later, in the same frame, and a scroll view
/// around a list of them reported its geometry twice in that frame, which SwiftUI logs as a fault.
@MainActor
@Suite("Rail rows lay out once")
struct RailRowLayoutTests {
    private nonisolated static let large = UIContentSizeCategory.large
    private nonisolated static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge

    /// Every size each row was laid out at, and every content height the scroll view reported.
    private final class Log {
        var rows: [Int: [CGSize]] = [:]
        var contentHeights: [CGFloat] = []
    }

    private struct Host: View {
        let log: Log

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0 ..< 4, id: \.self) { index in
                        RowLabel(title: "Dumbbell bench press", detail: "3 × 10 reps · 20 kg")
                            .railRow()
                            .onGeometryChange(for: CGSize.self, of: \.size) {
                                log.rows[index, default: []].append($0)
                            }
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
            .onScrollGeometryChange(for: CGFloat.self, of: \.contentSize.height) { _, height in
                log.contentHeights.append(height)
            }
        }
    }

    @Test("A list of rail rows is laid out once, at its final size", arguments: [large, ax5])
    func laidOutOnce(category: UIContentSizeCategory) throws {
        let log = Log()
        let host = UIHostingController(rootView: Host(log: log))
        let window = UIWindow.sceneless(hosting: host, at: category)
        defer { window.isHidden = true }
        for _ in 0 ..< 10 {
            window.layoutIfNeeded()
            RunLoop.main.run(mode: .default, before: .now)
        }
        try #require(log.rows.count == 4)
        for (index, sizes) in log.rows.sorted(by: { $0.key < $1.key }) {
            #expect(sizes.count == 1, "row \(index), \(category.rawValue): laid out at \(sizes)")
        }
        #expect(
            log.contentHeights.count == 1,
            "\(category.rawValue): content heights \(log.contentHeights)",
        )
    }
}

#endif
