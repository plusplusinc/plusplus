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
}

#endif
