// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

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
        let caret = Caret()
        let index = offset.map { draft.index(draft.startIndex, offsetBy: $0) } ?? draft.endIndex
        caret.selection = TextSelection(insertionPoint: index)
        return editing(draft, caret: caret)
    }

    private func editing(_ draft: String, caret: Caret) -> some View {
        EditableTitleContent(
            draft: .constant(draft),
            caret: caret,
            selection: .constant(caret.selection),
            defaultText: "New routine",
            isEditing: true,
            blinks: false,
            accessibilityLabel: "Routine name",
            accessibilityHint: "Renames the routine.",
            behavior: EmptyModifier(),
        )
        .padding(Spacing.md)
        .background(Color.pp(.background))
    }

    @Test("Editing the default: gray, with the _ under the N")
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
        let draft = "Arm and back"
        let caret = Caret()
        caret.selection = TextSelection(
            range: draft.index(draft.startIndex, offsetBy: 4) ..< draft.index(
                draft.startIndex,
                offsetBy: 7,
            ),
        )
        assertThemedSnapshots(of: editing(draft, caret: caret), width: Self.screenWidth)
    }
}

#endif
