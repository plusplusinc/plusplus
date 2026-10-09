import DesignSystem
import SwiftUI
import Testing

@Suite("Editable title rules")
struct EditableTitleTests {
    private let defaultText = "New routine"

    @Test("The default is the placeholder, so typing replaces it")
    func draftForDefault() {
        #expect(EditableTitle.draft(for: defaultText, defaultText: defaultText).isEmpty)
    }

    @Test("Editing a chosen name starts from that name")
    func draftForCustomName() {
        #expect(EditableTitle.draft(for: "Legs", defaultText: defaultText) == "Legs")
    }

    @Test("With no selection yet, the cursor is at the end")
    func insertionWithoutSelection() {
        #expect(EditableTitle.insertionPoint(of: nil, in: "Legs") == "Legs".endIndex)
    }

    @Test("The cursor follows an insertion point into the middle")
    func insertionInMiddle() {
        let draft = "Legs day"
        let index = draft.index(draft.startIndex, offsetBy: 4)
        let selection = TextSelection(insertionPoint: index)
        #expect(EditableTitle.insertionPoint(of: selection, in: draft) == index)
    }

    @Test("A range selection has no cursor")
    func insertionForRange() {
        let draft = "Legs day"
        let firstLetter = draft.startIndex ..< draft.index(after: draft.startIndex)
        let selection = TextSelection(range: firstLetter)
        #expect(EditableTitle.insertionPoint(of: selection, in: draft) == nil)
    }

    @Test("A selection left over from a longer draft puts the cursor at the end")
    func insertionPastEnd() {
        let longer = "Legs day"
        let selection = TextSelection(insertionPoint: longer.endIndex)
        #expect(EditableTitle.insertionPoint(of: selection, in: "Legs") == "Legs".endIndex)
    }

    @Test("The empty field reserves as many lines as the default text drawn in its place")
    func lineCount() {
        // At AX5 a line of the title is 68pt; "New routine" wraps to two.
        #expect(EditableTitle.lineCount(height: 136, lineHeight: 68) == 2)
        // Heights measured on the pixel grid are a fraction off.
        #expect(EditableTitle.lineCount(height: 135.33, lineHeight: 68) == 2)
        #expect(EditableTitle.lineCount(height: 29, lineHeight: 29) == 1)
        // Before anything is measured, the field is one line, as it was.
        #expect(EditableTitle.lineCount(height: 0, lineHeight: 0) == 1)
        #expect(EditableTitle.lineCount(height: 0, lineHeight: 29) == 1)
    }

    @Test("On one line, the cursor's cell is its offset")
    func cellOnOneLine() {
        #expect(EditableTitle.cursorCell(at: 0, in: "New routine", columns: 20) == (0, 0))
        #expect(EditableTitle.cursorCell(at: 4, in: "New routine", columns: 20) == (0, 4))
        #expect(EditableTitle.cursorCell(at: 11, in: "New routine", columns: 20) == (0, 11))
    }

    @Test("A word that does not fit moves to the next line, with the cursor in it")
    func cellAfterWordWrap() {
        // "Upper body" fills ten columns; "day" goes to the next line.
        #expect(EditableTitle.cursorCell(at: 11, in: "Upper body day", columns: 10) == (1, 0))
        #expect(EditableTitle.cursorCell(at: 14, in: "Upper body day", columns: 10) == (1, 3))
        // "New " fits, "routine" does not.
        #expect(EditableTitle.cursorCell(at: 11, in: "New routine", columns: 10) == (1, 7))
    }

    @Test("A cursor after a full line, or before a space past it, hangs past the edge")
    func cellHanging() {
        #expect(EditableTitle.cursorCell(at: 10, in: "Upper body", columns: 10) == (0, 10))
        #expect(EditableTitle.cursorCell(at: 10, in: "Upper body day", columns: 10) == (0, 10))
    }

    @Test("A hyphen ends a word, so a hyphenated name wraps after it")
    func cellAfterHyphen() {
        // "Push-" fits on the first line; "pull" goes to the next.
        #expect(EditableTitle.cursorCell(at: 5, in: "Push-pull", columns: 6) == (1, 0))
    }

    @Test("Several spaces past a full line keep the cursor in the cell past the edge")
    func cellInHangingSpaces() {
        #expect(EditableTitle.cursorCell(at: 12, in: "Upper body   ", columns: 10) == (0, 10))
    }

    @Test("A word longer than a line breaks between characters")
    func cellInLongWord() {
        #expect(EditableTitle.cursorCell(at: 5, in: "Shoulderpress", columns: 4) == (1, 1))
    }

    @Test(
        "One newline anywhere is a Return",
        arguments: ["Legs\n", "\nLegs", "Le\ngs", "\n"],
    )
    func returnAnywhere(draft: String) {
        #expect(EditableTitle.isReturn(draft))
    }

    @Test("Pasted lines are not a Return")
    func pasteIsNotReturn() {
        #expect(!EditableTitle.isReturn("Legs\nday\n"))
        #expect(!EditableTitle.isReturn("Legs\n\n"))
    }

    @Test(
        "An empty or blank edit restores the default",
        arguments: ["", "   ", "\n", " \t\n "],
    )
    func committedBlank(draft: String) {
        #expect(EditableTitle.committed(draft, defaultText: defaultText) == defaultText)
    }

    @Test("A real name is kept, trimmed")
    func committedName() {
        #expect(EditableTitle.committed("Legs", defaultText: defaultText) == "Legs")
        #expect(EditableTitle.committed("  Push day \n", defaultText: defaultText) == "Push day")
    }
}
