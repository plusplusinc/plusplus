// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// The title hands each change on as it is typed, by the rule `committed(_:from:)` holds, so a
/// name is kept however the edit is left, including ways that end no edit: the app leaving the
/// foreground, or the screen going away.
@MainActor
@Suite("Editable title hands on what is typed while the edit is open")
struct EditableTitleTypingTests {
    /// Every value the title handed on.
    private final class Log {
        var names: [String] = []
    }

    private struct Host: View {
        @State var name = ""
        @State var isEditing = false
        let suggestion: String?
        let log: Log

        var body: some View {
            EditableTitle(
                text: $name,
                isEditing: $isEditing,
                placeholder: "New routine",
                suggestion: suggestion,
                accessibilityLabel: "Routine name",
                accessibilityHint: "Renames the routine.",
            )
            .onChange(of: name) { _, name in log.names.append(name) }
            .frame(width: 370)
        }
    }

    /// Starts an edit on a title showing `suggestion`, types `keys` one at a time, and returns
    /// what the title handed on, with the edit still open.
    private func typed(_ keys: [String], over suggestion: String?) throws -> [String] {
        let log = Log()
        let host = UIHostingController(rootView: Host(suggestion: suggestion, log: log))
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        func field(in view: UIView) -> UITextView? {
            view as? UITextView ?? view.subviews.lazy.compactMap(field(in:)).first
        }
        let field = try #require(field(in: host.view))
        window.settle()
        try #require(field.becomeFirstResponder())
        window.settle()
        for key in keys {
            if key.isEmpty {
                field.deleteBackward()
            } else {
                field.insertText(key)
            }
            window.settle()
        }
        try #require(field.isFirstResponder, "The edit ended")
        return log.names
    }

    @Test("Each letter typed reaches the title before the edit ends")
    func typedLettersReachTheTitle() throws {
        #expect(try typed(["L", "e", "g"], over: nil) == ["L", "Le", "Leg"])
    }

    @Test("A suggestion opened and cleared hands on nothing, leaving the title unnamed")
    func clearedSuggestionStaysUnnamed() throws {
        // Deleting from the suggestion's end names the title for a moment, then leaves it
        // unnamed again once nothing is left.
        let names = try typed(["", "", ""], over: "Leg")
        #expect(names == ["Le", "L", ""])
    }

    @Test("Typing a suggestion back as it was leaves the title unnamed")
    func suggestionRetypedStaysUnnamed() throws {
        #expect(try typed(["", "g"], over: "Leg") == ["Le", ""])
    }
}

#endif
