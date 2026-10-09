import DesignSystem
import Testing

@Suite("Editable title rules")
struct EditableTitleTests {
    private let defaultText = "New routine"

    @Test("Editing the default starts empty, so typing replaces it")
    func draftForDefault() {
        #expect(EditableTitle.draft(forEditing: defaultText, defaultText: defaultText).isEmpty)
    }

    @Test("Editing a chosen name starts from that name")
    func draftForCustomName() {
        #expect(EditableTitle.draft(forEditing: "Legs", defaultText: defaultText) == "Legs")
    }

    @Test(
        "Return anywhere in the name is a Return",
        arguments: [
            ("Legs", "Legs\n"), ("Legs", "\nLegs"), ("Legs", "Le\ngs"), ("", "\n"),
            // Deleting everything and pressing Return, reaching the field as one change.
            ("Legs day", "\n"),
        ],
    )
    func returnAnywhere(oldDraft: String, newDraft: String) {
        #expect(EditableTitle.isReturn(from: oldDraft, to: newDraft))
    }

    @Test("Pasted lines are not a Return")
    func pasteIsNotReturn() {
        #expect(!EditableTitle.isReturn(from: "Legs", to: "Legs\nday"))
        #expect(!EditableTitle.isReturn(from: "Legs", to: "Legs\n\n"))
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
