import SwiftUI
import Testing
@testable import DesignSystem

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

    @Test("Return ends editing and inserts nothing")
    func newlineReturn() {
        #expect(EditableTitle.newlineEdit("\n") == ("", true))
    }

    @Test("A word arriving with Return, as autocorrect sends it, is inserted, and editing ends")
    func newlineWordWithReturn() {
        #expect(EditableTitle.newlineEdit("back\n") == ("back", true))
        #expect(EditableTitle.newlineEdit("body\u{2019}s\n") == ("body\u{2019}s", true))
    }

    @Test("Pasted lines become spaces, and editing goes on")
    func newlinePastedLines() {
        #expect(EditableTitle.newlineEdit("Legs\nday\n") == ("Legs day ", false))
        #expect(EditableTitle.newlineEdit("Legs\n\n") == ("Legs  ", false))
        // One newline with text after it is a paste too, not a Return.
        #expect(EditableTitle.newlineEdit("Push\nday") == ("Push day", false))
    }

    @Test("Text with no newline is inserted as it is", arguments: ["", "Legs", "上半身", "💪"])
    func newlineNone(text: String) {
        #expect(EditableTitle.newlineEdit(text) == (text, false))
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
