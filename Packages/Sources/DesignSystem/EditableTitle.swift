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
    /// The field's selection lives outside this view's state, so a moving caret redraws only the
    /// cursor and never updates the field while the keyboard is moving it.
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
        ZStack(alignment: .topLeading) {
            // A field's own placeholder stays on one line, truncated, so the default is drawn
            // here, wrapping like the text it stands for.
            if draft.isEmpty {
                Text(defaultText)
                    .foregroundStyle(.pp(isEditing ? .textSecondary : .textPrimary))
                    .accessibilityHidden(true)
            }
            field
        }
        .overlay(alignment: .top) {
            TitleCursor(caret: caret, draft: draft, defaultText: defaultText, isEditing: isEditing)
        }
        .ppScreenTitleFont()
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

    /// The tint is the caret's color, and the selection highlight's, so it is clear only while
    /// there is no range to highlight.
    private var field: some View {
        TextField(
            "",
            text: $draft,
            selection: $caret.selection,
            axis: .vertical,
        )
        .foregroundStyle(.pp(.textPrimary))
        .tint(isEditing && caret.isRange ? nil : .clear)
        .focused($isEditing)
        .submitLabel(.done)
        #if os(iOS)
        .textInputAutocapitalization(.sentences)
        #endif
        .onSubmit { isEditing = false }
        // A hardware keyboard's Return reaches a vertical field as a key press.
        .onKeyPress(.return) {
            isEditing = false
            return .handled
        }
        // The on-screen keyboard's Return reaches it as an inserted newline, wherever the caret
        // is. Newlines inside pasted text become spaces, since a title is one paragraph.
        .onChange(of: draft) { _, newDraft in
            guard newDraft.contains(where: \.isNewline) else { return }
            if Self.isReturn(newDraft) {
                draft = newDraft.filter { !$0.isNewline }
                isEditing = false
            } else {
                draft = String(newDraft.map { $0.isNewline ? " " : $0 })
                // The old selection indexes the old string.
                caret.selection = TextSelection(insertionPoint: draft.endIndex)
            }
        }
        .accessibilityLabel(Text(label))
        // The default is only a placeholder in the field, but it is still the name.
        .accessibilityValue(Text(verbatim: draft.isEmpty ? defaultText : draft))
        .accessibilityHint(Text(hint))
    }

    private func commit() {
        text = Self.committed(draft, defaultText: defaultText)
        draft = Self.draft(for: text, defaultText: defaultText)
    }
}

/// The field's selection. `isRange` changes only between a caret and a range, so the field,
/// which reads only that, is not updated as the caret moves.
@Observable
private final class Caret {
    var selection: TextSelection? {
        didSet {
            let isRange = selection != nil && EditableTitle
                .insertionPoint(of: selection, in: "") == nil
            if isRange != self.isRange {
                self.isRange = isRange
            }
        }
    }

    private(set) var isRange = false
}

/// The `_`: blinking from the moment editing starts or the caret moves, still at rest.
private struct TitleCursor: View {
    let caret: Caret
    let draft: String
    let defaultText: String
    let isEditing: Bool

    @State private var since = Date.now
    /// A character cell of the title, a little over: room past the trailing edge for a `_` that
    /// hangs after a full line.
    @ScaledMetric(relativeTo: .title2) private var spareCell: CGFloat = 16
    /// How far the `_` sits below the font's own underscore, so it reads as a cursor under the
    /// letter rather than a typed character: just past the tails of g, p, and y. Scaled with the
    /// title.
    @ScaledMetric(relativeTo: .title2) private var drop: CGFloat = 4.5
    @ObserveHotReload private var hotReload

    /// Matches the 1.06s cycle of a text cursor: on half, off half, no fade.
    private static let blinkInterval: TimeInterval = 0.53

    var body: some View {
        Group {
            if isEditing {
                TimelineView(.periodic(from: since, by: Self.blinkInterval)) { context in
                    let ticks = context.date.timeIntervalSince(since) / Self.blinkInterval
                    let isOn = Int(ticks.rounded()).isMultiple(of: 2)
                    underscore(isOn ? .pp(.textPrimary) : .clear)
                }
            } else {
                underscore(.pp(.borderStrong))
            }
        }
        .padding(.trailing, -spareCell)
        .padding(.bottom, -drop)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: caret.selection) {
            since = .now
        }
        .onChange(of: isEditing) {
            since = .now
        }
        .hotReloadable()
    }

    /// Where the cursor is in what the field shows, the draft or the placeholder, as a character
    /// offset: under the placeholder's first letter while editing, after the text at rest, and
    /// nowhere for a range selection.
    private var offset: Int? {
        if draft.isEmpty {
            return isEditing ? 0 : defaultText.count
        }
        guard isEditing else { return draft.count }
        return EditableTitle.insertionPoint(of: caret.selection, in: draft)
            .map { draft.distance(from: draft.startIndex, to: $0) }
    }

    /// One character cell of the title's monospaced font. Measured over many characters and
    /// lines, since a single measurement is rounded to the pixel grid and the error would add up
    /// across a line.
    private static func cell(in context: GraphicsContext) -> CGSize {
        let count = 50
        let unbounded = CGSize(width: CGFloat.infinity, height: .infinity)
        let row = context.resolve(Text(verbatim: String(repeating: "_", count: count)))
        let column = context.resolve(Text(verbatim: Array(repeating: "_", count: count)
                .joined(separator: "\n")))
        let one = context.resolve(Text(verbatim: "_")).measure(in: unbounded)
        return CGSize(
            width: row.measure(in: unbounded).width / CGFloat(count),
            height: (column.measure(in: unbounded).height - one.height) / CGFloat(count - 1),
        )
    }

    private func underscore(_ color: Color) -> some View {
        let shown = draft.isEmpty ? defaultText : draft
        let offset = offset
        return Canvas { context, size in
            guard let offset else { return }
            let mark = context.resolve(Text(verbatim: "_").foregroundStyle(color))
            let cell = Self.cell(in: context)
            let columns = max(1, Int((size.width - spareCell) / cell.width))
            let place = EditableTitle.cursorCell(at: offset, in: shown, columns: columns)
            let origin = CGPoint(
                x: CGFloat(place.column) * cell.width,
                y: CGFloat(place.line) * cell.height + drop,
            )
            context.draw(mark, at: origin, anchor: .topLeading)
        }
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
