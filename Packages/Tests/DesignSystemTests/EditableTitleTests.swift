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
