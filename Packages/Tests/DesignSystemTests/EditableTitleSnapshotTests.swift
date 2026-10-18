// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// The title while it is being edited, drawn from plain values: no focus, no keyboard. The `_`
/// is held lit, so the images do not depend on when in its blink they render. Where the real
/// text system puts the caret is the UI tests'; where the `_` draws for a caret is held here.
@Suite("Editable title while editing")
struct EditableTitleSnapshotTests {
    private static let screenWidth: CGFloat = 390

    /// The title being edited with `draft` in the field and the caret before the character at
    /// `caret`, or the end when it is nil.
    private func editing(_ draft: String, caret offset: Int? = nil) -> some View {
        let index = offset.map { draft.index(draft.startIndex, offsetBy: $0) } ?? draft.endIndex
        return editing(draft, selection: NSRange(index ..< index, in: draft))
    }

    private func editing(_ draft: String, selection: NSRange) -> some View {
        EditableTitleContent(
            draft: .constant(draft),
            selection: selection,
            placeholder: "New routine",
            shownPlaceholder: "New routine",
            isEditing: true,
            blinks: false,
            accessibilityLabel: "Routine name",
            accessibilityHint: "Renames the routine.",
        )
        .padding(Spacing.md)
        .background(Color.pp(.background))
    }

    @Test("Editing an unnamed title: the placeholder gray, with the _ under the N")
    func editingDefault() {
        assertThemedSnapshots(of: editing(""), width: Self.screenWidth)
    }

    /// At AX5 the name wraps to "Arm and" / "back", so the `_` is on line 2 there.
    @Test("The _ under the letter after the caret, mid-word")
    func caretMidWord() {
        assertThemedSnapshots(of: editing("Arm and back", caret: 9), width: Self.screenWidth)
    }

    /// The xxxl image holds it: three lines, the `_` under the i of drills.
    @Test("At AX5 the _ sits under line 2 of three, above line 3")
    func caretOnWrappedLine() {
        assertThemedSnapshots(
            of: editing("Hot beat drills and abs", caret: 11),
            width: Self.screenWidth,
        )
    }

    @Test("The _ under a y sits below its tail")
    func caretClearsDescenders() {
        assertThemedSnapshots(of: editing("gym yoga", caret: 4), width: Self.screenWidth)
    }

    /// The system highlight is drawn only around a focused field, so it is the UI tests'; this
    /// holds that no `_` is drawn with it.
    @Test("A range selection draws no _")
    func rangeSelection() {
        assertThemedSnapshots(
            of: editing("Arm and back", selection: NSRange(location: 4, length: 3)),
            width: Self.screenWidth,
        )
    }

    /// Before an emoji the `_` spans it, as wide as the emoji is drawn.
    @Test("Mid-way through a run of emoji, the _ is under the emoji after the caret")
    func caretInEmoji() {
        assertThemedSnapshots(
            of: editing("Legs 💪💪💪💪💪💪💪 and back", caret: 8),
            width: Self.screenWidth,
        )
    }

    /// Before a CJK character the `_` spans it, as wide as the character is drawn.
    @Test("Mid-way through a Chinese name, the _ is under the character after the caret")
    func caretInChinese() {
        assertThemedSnapshots(of: editing("上半身和下半身力量训练", caret: 4), width: Self.screenWidth)
    }
}

#endif
