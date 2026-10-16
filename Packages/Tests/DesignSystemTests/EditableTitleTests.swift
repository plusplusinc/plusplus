import SwiftUI
import Testing
@testable import DesignSystem
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@Suite("Editable title rules")
struct EditableTitleTests {
    @Test("A letter shuffles through the name's other letters, in its case")
    func standInLetters() throws {
        let name = "Squat and pull"
        let others = Set("squtndpl").subtracting(["a"])
        for swap in 0 ..< 50 {
            let standIn = try #require(EditableTitle.standIn(for: "a", at: 3, swap: swap, in: name))
            #expect(others.contains(standIn))
        }
        let capital = try #require(EditableTitle.standIn(for: "P", at: 5, swap: 0, in: "Push Pull"))
        #expect(capital.isUppercase && capital != "P")
    }

    @Test("The first character, and anything but a letter, lands at once")
    func standInNone() {
        #expect(EditableTitle.standIn(for: "S", at: 0, swap: 0, in: "Squat") == nil)
        for character: Character in [" ", "-", "1", "\u{2019}"] {
            #expect(EditableTitle.standIn(for: character, at: 2, swap: 0, in: "Squat") == nil)
        }
        #expect(EditableTitle.standIn(for: "a", at: 1, swap: 0, in: "Aa") == nil)
    }

    @Test("A short trail shuffles behind the lead, and landed letters ease from blue")
    func typingTrail() {
        let lead = SuggestionTiming.leadInterval
        let start = EditableTitle.typingFrame(of: "Squat and pull", at: 0)
        #expect(start.shown == "S")
        #expect(start.standIns.isEmpty)
        #expect(start.tints[0] == 1)

        let trail = EditableTitle.typingFrame(of: "Squat and pull", at: lead * 4 + lead / 2)
        #expect(trail.shown == "Squat")
        #expect(Set(trail.standIns.keys) == [3, 4])
        #expect(trail.tints[3] == 1)
        let landed = trail.tints[1] ?? 0
        #expect(landed > 0 && landed < 1)
        #expect(trail.cursorTint == 1)
    }

    @Test("Once its time is up, the whole text has landed in gray")
    func typingEnds() {
        let text = "Squat and pull"
        let end = EditableTitle.typingFrame(of: text, at: EditableTitle.typingDuration(of: text))
        #expect(end.shown == text)
        #expect(end.standIns.isEmpty)
        #expect(end.tints.isEmpty)
        #expect(end.cursorTint == 0)
        #expect(EditableTitle.typingDuration(of: text) < 0.5)
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

    /// Text as the field holds it: in a text storage, which Swift reads as UTF-16, unlike the
    /// UTF-8 of a string built in Swift. An index from it read past the end of a Swift string
    /// with a character beyond ASCII traps.
    private func fieldText(_ text: String) -> String {
        NSTextStorage(string: text).string
    }

    @Test("Return after an autocorrection puts the cursor at the end of what is left")
    func returnAfterAutocorrection() {
        // Autocorrect turned "bodys" into "body’s", then Return added a newline, with the
        // field's caret after it: one character past the end of the draft without it.
        var draft = fieldText("Total body\u{2019}s\n")
        let caret = Caret()
        caret.selection = TextSelection(insertionPoint: draft.endIndex)

        #expect(EditableTitle.takeNewlines(in: &draft, caret: caret))
        #expect(draft == "Total body\u{2019}s")
        #expect(EditableTitle.insertionPoint(of: caret.selection, in: draft) == draft.endIndex)
    }

    @Test("Pasted lines become spaces, and the cursor goes to the end")
    func pastedLines() {
        var draft = fieldText("Legs\nday\u{2019}s\n")
        let caret = Caret()
        caret.selection = TextSelection(insertionPoint: draft.endIndex)

        #expect(!EditableTitle.takeNewlines(in: &draft, caret: caret))
        #expect(draft == "Legs day\u{2019}s ")
        #expect(EditableTitle.insertionPoint(of: caret.selection, in: draft) == draft.endIndex)
    }

    @Test("Text set from outside the field takes the caret to its end, past the old one's")
    func replacedDraft() {
        var draft = fieldText("Push d\u{00E9}j\u{00E0} vu")
        let caret = Caret()
        caret.selection = TextSelection(insertionPoint: draft.endIndex)

        caret.replace(&draft, with: "D\u{00E9}j\u{00E0}")
        #expect(EditableTitle.insertionPoint(of: caret.selection, in: draft) == draft.endIndex)
    }

    @Test("The field is as many lines as its text wraps to, and one before it is measured")
    func lineCount() {
        // At AX5 about 10 cells fit across; "New routine" wraps to two.
        #expect(EditableTitle.lineCount(of: "New routine", columns: 10) == 2)
        #expect(EditableTitle.lineCount(of: "New routine", columns: 24) == 1)
        #expect(EditableTitle.lineCount(of: "Hot beat drills and abs", columns: 10) == 3)
        #expect(EditableTitle.lineCount(of: "", columns: 10) == 1)
        // Spaces past a full line hang past its edge rather than starting another.
        #expect(EditableTitle.lineCount(of: "Push      ", columns: 4) == 1)
        #expect(EditableTitle.lineCount(of: "New routine", columns: nil) == 1)
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

    @Test("Lines break where the field breaks them, even leaving one word on the last line")
    func lineBreaksAsTheField() {
        // "Legs and " fits in ten columns, its space hanging; "back" goes to the next line.
        #expect(EditableTitle.lineBreaks(in: "Legs and back", columns: 10) == [9])
        #expect(EditableTitle.lineBreaks(in: "Legs and back", columns: 13).isEmpty)
        #expect(EditableTitle.lineBreaks(in: "Shoulderpress", columns: 4) == [4, 8, 12])
        #expect(EditableTitle.lineBreaks(in: "Push-pull", columns: 6) == [5])
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
        "An empty or blank edit leaves the title unnamed, showing the placeholder",
        arguments: ["", "   ", "\n", " \t\n "],
    )
    func committedBlank(draft: String) {
        #expect(EditableTitle.committed(draft).isEmpty)
    }

    @Test("A suggestion committed unchanged stays a suggestion, leaving the title unnamed")
    func committedSuggestionUnchanged() {
        #expect(EditableTitle.committed("Leg day", from: "Leg day").isEmpty)
        #expect(EditableTitle.committed(" Leg day ", from: "Leg day").isEmpty)
    }

    @Test("A suggestion changed is the title, and cleared leaves it unnamed")
    func committedSuggestionChanged() {
        #expect(EditableTitle.committed("Leg day 2", from: "Leg day") == "Leg day 2")
        #expect(EditableTitle.committed("", from: "Leg day").isEmpty)
    }

    @Test("A real name is kept, trimmed")
    func committedName() {
        #expect(EditableTitle.committed("Legs") == "Legs")
        #expect(EditableTitle.committed("  Push day \n") == "Push day")
    }
}
