// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing
import UIKit

/// A move off the current exercise lands the next row by what the current one gives back as it
/// shrinks, its pitch at rest. A screen that opens with the workout under way never saw the
/// current row at rest, so it measures a copy (`reportingRailPitch(of:isOn:to:)`): the pitch it
/// reports has to be the one the same row stands at on the rail at rest, or the move lands short
/// and the list moves again after it.
@MainActor
@Suite("A grown row reports the pitch it rests at")
struct RailRowPitchTests {
    private nonisolated static let large = UIContentSizeCategory.large
    private nonisolated static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge

    private final class Log {
        var reported: CGFloat?
        var resting: CGFloat?
    }

    private struct Host: View {
        let log: Log
        let title: String
        private let detail = ["3 × 10 reps", "25 lb/side"]

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content(focus: RowFocus(
                        progress: "Set 1 of 3",
                        equipment: ["Dumbbells", "Bench"],
                        figures: [
                            .init(number: "10", unit: "reps"),
                            .init(number: "25", unit: "lb"),
                        ],
                        spokenFigures: "10 reps, 25 pounds",
                    ))
                    .railRow()
                    .reportingRailPitch(isOn: true) { content(focus: nil) } to: { log.reported = $0
                    }
                    content(focus: nil)
                        .railRow()
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { log.resting = $0 }
                }
                .padding(.horizontal, Spacing.md)
            }
        }

        /// A row's content, as the routine screen gives `railRow()` it.
        private func content(focus: RowFocus?) -> some View {
            LabelWithRest(
                label: RowLabel(title: title, detail: detail, focus: focus),
                rest: .closed,
            )
        }
    }

    @Test(
        "A grown row reports the height it stands at on the rail at rest",
        arguments: [large, ax5],
        ["Dumbbell bench press", "Single-arm dumbbell Romanian deadlift to row"],
    )
    func reportsRestingPitch(category: UIContentSizeCategory, title: String) throws {
        let log = Log()
        let host = UIHostingController(rootView: Host(log: log, title: title))
        let window = UIWindow.sceneless(hosting: host, at: category)
        defer { window.isHidden = true }
        window.settle()
        let resting = try #require(log.resting)
        let reported = try #require(log.reported, "no pitch reported")
        #expect(
            abs(reported - resting) < 0.5,
            "\(category.rawValue), \(title): reported \(reported), rests at \(resting)",
        )
    }
}

#endif
