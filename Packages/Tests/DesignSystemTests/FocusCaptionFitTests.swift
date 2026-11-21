// Runs only where UIKit exists, as the suites that host views do.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// The caption line's end words fit beside the lead as it reads while a set is current, "Round 1
/// of 3", never pushed under it by the room "done" keeps, which shows only while they are faded.
@MainActor
@Suite("Caption line's fit")
struct FocusCaptionFitTests {
    private static func focus(word: String, isDone: Bool, side: String? = nil) -> RowFocus {
        RowFocus(
            place: SetPlace(
                word: word,
                number: 1,
                total: 3,
                isDone: isDone,
                locale: Locale(identifier: "en_US"),
            ),
            side: side,
            figures: [.init(number: "10", unit: "reps")],
            spokenFigures: "10 reps",
            after: "then rest 0:05",
        )
    }

    private static func size(_ view: some View, width: CGFloat = .infinity) -> CGSize {
        let host = UIHostingController(rootView: view)
        host.traitOverrides.preferredContentSizeCategory = .large
        return host.sizeThatFits(in: CGSize(width: width, height: .infinity))
    }

    /// The narrowest width "then rest 0:05" fits beside the lead at, as it fit before "done".
    private static func tightWidth(_ focus: RowFocus) -> CGFloat {
        let lead = size(ProgressLine(focus: focus, keepsDoneRoom: false)).width
        let end = size(Text(verbatim: "then rest 0:05").font(.ppCurrentProgress)).width
        return ceil(lead + Spacing.md + end) + 1
    }

    @Test("Round 1 of 3: one line beside then rest, with a set current and while resting")
    func round() {
        let current = Self.focus(word: "Round", isDone: false)
        let lineHeight = Self.size(ProgressLine(focus: current)).height
        let width = Self.tightWidth(current)
        // "done"'s room is real: kept laid out, the lead is wider than it reads with the ends.
        let withDone = Self.size(ProgressLine(focus: current)).width
        let without = Self.size(ProgressLine(focus: current, keepsDoneRoom: false)).width
        #expect(withDone > without)
        for isDone in [false, true] {
            let caption = FocusCaption(
                focus: Self.focus(word: "Round", isDone: isDone),
                isResting: isDone,
            )
            #expect(Self.size(caption, width: width).height == lineHeight, "done \(isDone)")
        }
    }

    @Test("Set 1 of 3 · Right: one line beside then rest, as before done")
    func sided() {
        let current = Self.focus(word: "Set", isDone: false, side: "Right")
        let lineHeight = Self.size(ProgressLine(focus: current)).height
        let width = Self.tightWidth(current)
        for isDone in [false, true] {
            let caption = FocusCaption(
                focus: Self.focus(word: "Set", isDone: isDone, side: "Right"),
                isResting: isDone,
            )
            #expect(Self.size(caption, width: width).height == lineHeight, "done \(isDone)")
        }
    }
}

#endif
