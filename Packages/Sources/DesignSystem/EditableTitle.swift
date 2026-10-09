import SwiftUI

/// A screen title that is edited in place.
///
/// At rest it reads as a title with a faint trailing `_`. Tapping it focuses the field: the `_`
/// becomes the blinking cursor and the keyboard rises. The `_` marks the insertion point
/// wherever it is, under the character that typing will push along, or after the last one.
/// The system caret is hidden, so the `_` is the only cursor there is; a range selection shows
/// the system highlight instead.
///
/// The default text is the field's placeholder, never its contents: tapping it shows it gray with
/// the `_` under its first letter, typing replaces it, and ending with nothing keeps it.
///
/// The field only takes input. What shows is one `Text` drawn over it, the same view at rest and
/// while editing, so starting an edit cannot move the title.
public struct EditableTitle: View {
    @Binding private var text: String
    private let defaultText: String
    private let label: LocalizedStringKey
    private let hint: LocalizedStringKey

    @State private var draft: String
    @State private var selection: TextSelection?
    @State private var editingSince = Date.now
    @FocusState private var isEditing: Bool
    @ObserveHotReload private var hotReload

    /// Matches the 1.06s cycle of a text cursor: on half, off half, no fade.
    private static let blinkInterval: TimeInterval = 0.53
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
        _draft = State(initialValue: Self.draft(
            for: text.wrappedValue,
            defaultText: defaultText,
        ))
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
    public static func insertionPoint(of selection: TextSelection?, in draft: String) -> String
        .Index?
    {
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

    public var body: some View {
        ZStack(alignment: .topLeading) {
            field
            overlay
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
                selection = TextSelection(insertionPoint: draft.endIndex)
                editingSince = .now
            } else {
                commit()
            }
        }
        // A moved cursor shows at once, as the system caret does.
        .onChange(of: selection) {
            editingSince = .now
        }
        .onChange(of: text) { _, newText in
            if !isEditing {
                draft = Self.draft(for: newText, defaultText: defaultText)
            }
        }
        .hotReloadable()
    }

    /// The field takes taps, typing, and selection; its own text, placeholder, and caret are
    /// clear, since `overlay` draws them. The tint is the caret's color, and the selection
    /// highlight's, so it is clear only while there is no range to highlight.
    private var field: some View {
        TextField(
            "",
            text: $draft,
            selection: $selection,
            prompt: Text(defaultText).foregroundStyle(.clear),
            axis: .vertical,
        )
        .foregroundStyle(.clear)
        .tint(isEditing && Self.insertionPoint(of: selection, in: draft) == nil ? nil : .clear)
        .focused($isEditing)
        .submitLabel(.done)
        .autocorrectionDisabled()
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
                selection = TextSelection(insertionPoint: draft.endIndex)
            }
        }
        .accessibilityLabel(Text(label))
        // The default is only a placeholder in the field, but it is still the name.
        .accessibilityValue(Text(verbatim: draft.isEmpty ? defaultText : draft))
        .accessibilityHint(Text(hint))
    }

    /// The title as it shows, with the `_`: blinking from the moment editing starts, still at
    /// rest. Only the `_` blinks; the text stays the same between ticks.
    private var overlay: some View {
        Group {
            if isEditing {
                let title = shownText()
                TimelineView(.periodic(from: editingSince, by: Self.blinkInterval)) { context in
                    let ticks = context.date.timeIntervalSince(editingSince) / Self.blinkInterval
                    title.textRenderer(CursorRenderer(
                        color: Int(ticks.rounded()).isMultiple(of: 2) ? .pp(.textPrimary) : .clear,
                    ))
                }
            } else {
                shownText()
                    .textRenderer(CursorRenderer(color: .pp(.borderStrong)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The draft, or the default as a placeholder, followed by a clear thin space and `_` that
    /// reserve the cursor's place after the last character; the thin space keeps it from
    /// tucking under a letter with an overhang, like a final "e". It is always laid out, so
    /// moving the cursor never rewraps the text. With the cursor before a character, that
    /// character is tagged instead. A range selection has no `_`.
    private func shownText() -> Text {
        let isPlaceholder = draft.isEmpty
        let shown = isPlaceholder ? defaultText : draft
        let cursor: String.Index? = if !isEditing {
            shown.endIndex
        } else if isPlaceholder {
            shown.startIndex
        } else {
            Self.insertionPoint(of: selection, in: draft)
        }
        let title: Text
        if let cursor, cursor < shown.endIndex {
            let after = shown.index(after: cursor)
            title = Text("""
            \(Text(shown[..<cursor]))\
            \(Text(shown[cursor ..< after]).customAttribute(CursorTarget()))\
            \(Text(shown[after...]))
            """)
        } else {
            title = Text(verbatim: shown)
        }
        let mark = Text(verbatim: "\u{2009}_")
            .customAttribute(CursorMark(isShown: cursor != nil))
            .foregroundStyle(.clear)
        let color = Color.pp(isPlaceholder && isEditing ? .textSecondary : .textPrimary)
        return Text("\(title.foregroundStyle(color))\(mark)")
    }

    private func commit() {
        text = Self.committed(draft, defaultText: defaultText)
        draft = Self.draft(for: text, defaultText: defaultText)
    }
}

/// Tags the trailing thin space and `_` that reserve the cursor's place at the end; a range
/// selection keeps the place without a cursor.
private struct CursorMark: TextAttribute {
    var isShown: Bool
}

/// Tags the character the cursor sits before, when that is not the end.
private struct CursorTarget: TextAttribute { }

/// Draws the shown title and its `_`: under the character tagged as the cursor's target, or else
/// in the place reserved after the last character.
private struct CursorRenderer: TextRenderer {
    /// Clear for the blink's dark half.
    var color: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var reserved: CGPoint?
        var target: CGPoint?
        for line in layout {
            for run in line {
                if let mark = run[CursorMark.self] {
                    // The run is the thin space and the `_`; the `_` is its last glyph.
                    if mark.isShown, let last = run.indices.last {
                        reserved = Text.Layout.RunSlice(run: run, indices: last ..< run.endIndex)
                            .typographicBounds.origin
                    }
                    continue
                }
                if run[CursorTarget.self] != nil, target == nil {
                    target = run.typographicBounds.origin
                }
                context.draw(run)
            }
        }
        // A run drawn away from where it was laid out does not show, so the `_` is drawn as its
        // own text, its baseline on the cursor's.
        guard let baseline = target ?? reserved else { return }
        let underscore = context.resolve(Text(verbatim: "_").foregroundStyle(color))
        let size = underscore.measure(in: CGSize(width: CGFloat.infinity, height: .infinity))
        let origin = CGPoint(x: baseline.x, y: baseline.y - underscore.firstBaseline(in: size))
        context.draw(underscore, in: CGRect(origin: origin, size: size))
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
