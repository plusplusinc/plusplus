import SwiftUI

/// A screen title that is edited in place.
///
/// At rest it reads as a title with a faint trailing `_`. Tapping it focuses the field: the `_`
/// becomes the blinking cursor and the keyboard rises. The `_` marks the insertion point
/// wherever it is, under the character that typing will push along, or after the last one. The
/// system caret is hidden, so the `_` is the only cursor there is; a range selection shows the
/// system highlight instead.
///
/// The default text is the field's placeholder, never its contents: tapping it shows it gray with
/// the `_` under its first letter, typing replaces it, and ending with nothing keeps it.
///
/// The field draws its own text, so everything the keyboard shows in it (suggestions, inline
/// predictions, text being composed) shows as in any field. The `_` is drawn over it by
/// `TitleCursor`. The title is monospaced, so the `_` is one character cell wide and its place
/// follows from the text alone: `cursorCell(at:in:columns:)` wraps the text as the field does.
public struct EditableTitle: View {
    @Binding private var text: String
    private let defaultText: String
    private let label: LocalizedStringKey
    private let hint: LocalizedStringKey

    @State private var draft: String
    /// The field's selection, which the text system writes as the caret moves.
    @State private var caret = Caret()
    @FocusState private var isEditing: Bool
    @ObserveHotReload private var hotReload

    private static let minimumTouchTarget: CGFloat = 44

    public init(
        text: Binding<String>,
        defaultText: String,
        accessibilityLabel: LocalizedStringKey,
        accessibilityHint: LocalizedStringKey,
    ) {
        _text = text
        self.defaultText = defaultText
        label = accessibilityLabel
        hint = accessibilityHint
        _draft = State(initialValue: Self.draft(for: text.wrappedValue, defaultText: defaultText))
    }

    /// What the field holds for a title: empty for the default, which shows as the placeholder,
    /// so typing replaces it.
    public static func draft(for text: String, defaultText: String) -> String {
        text == defaultText ? "" : text
    }

    /// Whether a draft holds a press of Return: a single newline, wherever the caret was and
    /// whatever else the same change typed or replaced. More than one came from pasted lines.
    public static func isReturn(_ draft: String) -> Bool {
        draft.count(where: \.isNewline) == 1
    }

    /// The title an edit leaves behind: trimmed, and the default when nothing is left.
    public static func committed(_ draft: String, defaultText: String) -> String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultText : trimmed
    }

    /// Where the `_` goes in the draft: the insertion point, or nil for a range selection, which
    /// shows the system highlight instead. No selection yet is the end.
    public static func insertionPoint(
        of selection: TextSelection?,
        in draft: String,
    ) -> String.Index? {
        switch selection?.indices {
        case nil:
            draft.endIndex
        case let .selection(range) where range.isEmpty:
            // A selection can trail the draft by one change, and an index into the old string
            // may lie past the end of this one or inside one of its characters.
            String.Index(range.lowerBound, within: draft) ?? draft.endIndex
        default:
            nil
        }
    }

    /// How many lines a text `height` tall holds, at `lineHeight` a line: at least one, and one
    /// before either is measured. Rounded, since measured heights land on the pixel grid.
    public static func lineCount(height: CGFloat, lineHeight: CGFloat) -> Int {
        guard lineHeight > 0 else { return 1 }
        return max(1, Int((height / lineHeight).rounded()))
    }

    /// The line and column of the cell the cursor marks, for a cursor before the character at
    /// `offset` (or after the last one), in monospaced text wrapped at `columns` cells the way the
    /// field wraps it: a word that does not fit moves to the next line, a word longer than a line
    /// breaks between characters, a hyphen or dash ends a word, and spaces never wrap, hanging
    /// past the edge. A cursor in those spaces, or after a full last line, stays in the cell past
    /// the edge, where the field puts its caret.
    public static func cursorCell(
        at offset: Int,
        in text: String,
        columns: Int,
    ) -> (line: Int, column: Int) {
        let characters = Array(text)
        var cells: [(line: Int, column: Int)] = []
        var line = 0
        var column = 0
        var index = 0
        while index < characters.count {
            if characters[index] == " " {
                cells.append((line, column))
                column += 1
                index += 1
                continue
            }
            let wordEnd = characters[index...].firstIndex { $0 == " " || Self.breaksAfter($0) }
                .map { characters[$0] == " " ? $0 : $0 + 1 } ?? characters.count
            if column > 0, column + (wordEnd - index) > columns {
                line += 1
                column = 0
            }
            for _ in index ..< wordEnd {
                if column >= columns {
                    line += 1
                    column = 0
                }
                cells.append((line, column))
                column += 1
            }
            index = wordEnd
        }
        let cell = offset < cells.count ? cells[offset] : (line: line, column: column)
        return (cell.line, min(cell.column, columns))
    }

    private static func breaksAfter(_ character: Character) -> Bool {
        "-\u{2010}\u{2013}\u{2014}".contains(character)
    }

    public var body: some View {
        EditableTitleContent(
            draft: $draft,
            caret: caret,
            selection: $caret.selection,
            defaultText: defaultText,
            isEditing: isEditing,
            blinks: true,
            accessibilityLabel: label,
            accessibilityHint: hint,
            behavior: TitleFieldBehavior(isEditing: $isEditing, draft: $draft, caret: caret),
        )
        // The field is only as tall as its text. Behind it, a target at least 44pt tall reaches
        // down past a short title (above, the navigation bar takes the taps), and a tap there
        // focuses the field as a tap on the text does. A background takes no layout space, so
        // callers space the title like any other text.
        .background(alignment: .top) {
            Color.clear
                .frame(minHeight: Self.minimumTouchTarget)
                .contentShape(.rect)
                .onTapGesture { isEditing = true }
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                // The tap that focuses the field leaves the caret at the start or selects
                // everything, not where it landed, so editing starts at the end. Taps once
                // editing place the caret where they land.
                caret.selection = TextSelection(insertionPoint: draft.endIndex)
            } else {
                commit()
            }
        }
        .onChange(of: text) { _, newText in
            if !isEditing {
                draft = Self.draft(for: newText, defaultText: defaultText)
            }
        }
        .hotReloadable()
    }

    private func commit() {
        text = Self.committed(draft, defaultText: defaultText)
        draft = Self.draft(for: text, defaultText: defaultText)
    }
}

/// What the title's field does: takes focus, and ends editing on Return. Separate from how the
/// title is drawn, since only a view's own `@FocusState` can focus a field, so a snapshot can
/// draw the editing title without focusing anything.
private struct TitleFieldBehavior: ViewModifier {
    let isEditing: FocusState<Bool>.Binding
    @Binding var draft: String
    let caret: Caret
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        content
            .focused(isEditing)
            .submitLabel(.done)
            #if os(iOS)
            .textInputAutocapitalization(.sentences)
            #endif
            .onSubmit { isEditing.wrappedValue = false }
            // A hardware keyboard's Return reaches a vertical field as a key press.
            .onKeyPress(.return) {
                isEditing.wrappedValue = false
                return .handled
            }
            // The on-screen keyboard's Return reaches it as an inserted newline, wherever the
            // caret is. Newlines inside pasted text become spaces, since a title is one paragraph.
            .onChange(of: draft) { _, newDraft in
                guard newDraft.contains(where: \.isNewline) else { return }
                if EditableTitle.isReturn(newDraft) {
                    draft = newDraft.filter { !$0.isNewline }
                    isEditing.wrappedValue = false
                } else {
                    draft = String(newDraft.map { $0.isNewline ? " " : $0 })
                    // The old selection indexes the old string.
                    caret.selection = TextSelection(insertionPoint: draft.endIndex)
                }
            }
            .hotReloadable()
    }
}

#Preview {
    @Previewable @State var name = "New routine"
    EditableTitle(
        text: $name,
        defaultText: "New routine",
        accessibilityLabel: "Routine name",
        accessibilityHint: "Renames the routine.",
    )
    .padding()
    .background(Color.pp(.background))
}
