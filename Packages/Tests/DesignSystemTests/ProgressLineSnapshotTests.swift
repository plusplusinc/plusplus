// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// The line under the current exercise's set bars in each of its states, one under another:
/// "Set 1 of 3"; resting after it, "Set 1 of 3 done"; a sided set's "Set 2 of 3 · Left"; resting
/// after one, "done" in the side's place, at the side's start; a superset's "Round 1 of 3". At AX5
/// the side, or "done", goes under the set.
@MainActor
@Suite("Progress line")
struct ProgressLineSnapshotTests {
    private static func line(
        _ number: Int,
        word: String = "Set",
        isDone: Bool = false,
        side: String? = nil,
    ) -> some View {
        ProgressLine(focus: RowFocus(
            place: SetPlace(word: word, number: number, total: 3, isDone: isDone),
            side: side,
            figures: [],
            spokenFigures: "",
        ))
    }

    @Test("Each state's words, \"done\" and a side sharing one place")
    func states() {
        let view = VStack(alignment: .leading, spacing: Spacing.md) {
            Self.line(1)
            Self.line(1, isDone: true)
            Self.line(2, side: "Left")
            Self.line(2, isDone: true, side: "Right")
            Self.line(1, word: "Round")
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pp(.background))
        assertThemedSnapshots(of: view, width: 390)
    }
}

#endif
