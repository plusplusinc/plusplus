import SwiftUI

/// How many character cells the title's cell is measured over, since a single measurement is
/// rounded to the pixel grid and the error would add up across a line.
private let measuredCells = 50

/// The title drawn from plain values: what the field holds, whether it is being edited, and the
/// caret. `EditableTitle` feeds it and owns focus; snapshots render it directly.
struct EditableTitleContent<Behavior: ViewModifier>: View {
    @Binding var draft: String
    /// The field's selection lives outside the title's state, so a moving caret redraws only the
    /// cursor and never updates the field while the keyboard is moving it.
    let caret: Caret
    /// What the field reads and writes the selection through. In the app it must be
    /// `$caret.selection`, or the `_` stops following the caret. A field that is not focused
    /// writes its own selection back as it renders, so a snapshot passes one that ignores writes
    /// and keeps the caret it was given.
    @Binding var selection: TextSelection?
    /// The name an empty field stands for, which VoiceOver reads.
    let placeholder: String
    /// The placeholder as drawn, partway through typing in when it has just changed.
    let shownPlaceholder: String
    /// Whether what an empty field shows is a suggestion rather than the placeholder.
    var isSuggested = false
    /// Below 1 while the old placeholder fades out for a new one.
    var placeholderOpacity = 1.0
    /// The letters of `shownPlaceholder` still scrambling as it types in, by index, each drawn
    /// as its stand-in in the rail's joining blue.
    var standIns: [Int: Character] = [:]
    /// How far each character of `shownPlaceholder` is drawn in the rail's joining blue rather
    /// than the placeholder's gray, by index, from 0 to 1. Missing is 0.
    var tints: [Int: Double] = [:]
    /// How far the `_` at rest is drawn in the joining blue, from 0 to 1, breathing in step:
    /// while a new placeholder fades the old one out and types in.
    var cursorTint = 0.0
    let isEditing: Bool
    /// Whether the `_` blinks while editing, and pulses at rest. Snapshots hold it lit, however
    /// long after the view was made they render.
    let blinks: Bool
    let accessibilityLabel: LocalizedStringKey
    let accessibilityHint: LocalizedStringKey
    /// What the field does with focus, Return, and pasted lines: the wrapper's.
    let behavior: Behavior

    /// The title's width, and the width and height of one character cell of its monospaced font.
    @State private var width: CGFloat = 0
    @State private var cellWidth: CGFloat = 0
    @State private var lineHeight: CGFloat = 0
    /// The height of what the field shows, laid out as `Text` at the title's width: the draft, or
    /// the placeholder as drawn.
    @State private var shownHeight: CGFloat = 0
    @ObserveHotReload private var hotReload

    var body: some View {
        ZStack(alignment: .topLeading) {
            // A field's own placeholder stays on one line, truncated, so the placeholder is drawn
            // here, wrapping like the text it stands for.
            if draft.isEmpty {
                Text(drawnPlaceholder)
                    .foregroundStyle(restingColor)
                    .opacity(placeholderOpacity)
                    // With Reduce Motion a new placeholder crossfades in rather than typing.
                    .contentTransition(.opacity)
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) {
                        shownHeight = $0
                    }
            }
            // The field is exactly as many lines tall as what it shows wraps to, the draft or the
            // placeholder drawn in its place: an empty field is one line, and VoiceOver frames
            // the field. A range open at the top would size the field from its own text layout,
            // which keeps the height of a larger font after the text size shrinks until the text
            // changes; a closed range sizes it from the font. A frame around the field would not
            // do: the field stays as tall as its lines inside any frame.
            field
                .lineLimit(lines ... lines)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) {
            width = $0
        }
        .background {
            Text(verbatim: String(repeating: "_", count: measuredCells))
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGSize.self, of: \.size) {
                    cellWidth = $0.width / CGFloat(measuredCells)
                    lineHeight = $0.height
                }
        }
        .background(alignment: .topLeading) {
            // The draft, wrapped by the text system rather than counted in cells, so characters
            // wider than a cell, such as emoji and CJK, are counted as wide as they are. `Text`
            // lays out again when the font changes, so the height is never a size behind. An
            // empty field measures the placeholder drawn in its place instead.
            if !draft.isEmpty {
                Text(verbatim: draft)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) {
                        shownHeight = $0
                    }
            }
        }
        .overlay(alignment: .top) {
            TitleCursor(
                caret: caret,
                draft: draft,
                placeholder: shownPlaceholder,
                columns: columns,
                isEditing: isEditing,
                tint: cursorTint,
                blinks: blinks,
            )
        }
        .ppScreenTitleFont()
        .hotReloadable()
    }

    /// How many character cells fit across the title, once both are measured.
    private var columns: Int? {
        guard width > 0, cellWidth > 0 else { return nil }
        return max(1, Int(width / cellWidth))
    }

    /// What the field shows: its draft, or the placeholder drawn in its place.
    private var shown: String {
        draft.isEmpty ? shownPlaceholder : draft
    }

    /// How many lines the field shows: the more of the cell model's count, which wraps as the
    /// field does but counts every character one cell wide, and the measured `Text`'s, which
    /// sees characters wider than a cell. The larger only ever adds room, never cuts a line off.
    private var lines: Int {
        let counted = columns.map { EditableTitle.lineBreaks(in: shown, columns: $0).count + 1 }
        let measured = EditableTitle.lineCount(height: shownHeight, lineHeight: lineHeight)
        return max(counted ?? 1, measured)
    }

    /// The placeholder as drawn: broken into lines where the field would break them, each letter
    /// still shuffling as its stand-in, and each tinted as far toward blue as it is.
    private var drawnPlaceholder: AttributedString {
        let breaks = Set(columns
            .map { EditableTitle.lineBreaks(in: shownPlaceholder, columns: $0) } ?? [])
        var drawn = AttributedString()
        for (index, character) in shownPlaceholder.enumerated() {
            if breaks.contains(index) {
                drawn += AttributedString("\n")
            }
            var piece = AttributedString(String(standIns[index] ?? character))
            if let tint = tints[index], tint > 0 {
                piece.foregroundColor = restingColor.mix(with: .pp(.railJoin), by: tint)
            }
            drawn += piece
        }
        return drawn
    }

    /// White for a suggestion at rest, as a name is. Gray for the placeholder, and for a
    /// suggestion in a field emptied while editing, where it is only a hint at what ending with
    /// nothing brings back.
    private var restingColor: Color {
        .pp(isSuggested && !isEditing ? .textPrimary : .textSecondary)
    }

    /// The tint is the caret's color, and the selection highlight's, so it is clear only while
    /// there is no range to highlight.
    private var field: some View {
        TextField(
            "",
            text: $draft,
            selection: $selection,
            axis: .vertical,
        )
        .foregroundStyle(.pp(.textPrimary))
        .tint(isEditing && caret.isRange ? nil : .clear)
        .modifier(behavior)
        .accessibilityLabel(Text(accessibilityLabel))
        // The placeholder is not in the field, but it is still the name.
        .accessibilityValue(Text(verbatim: draft.isEmpty ? placeholder : draft))
        .accessibilityHint(Text(accessibilityHint))
    }
}

/// The field's selection. `isRange` changes only between a caret and a range, so the field,
/// which reads only that, is not updated as the caret moves.
///
/// The selection indexes the text it was made for, and the `_` reads it in the draft drawn with
/// it, so the two must always hold the same text. The field writes both together, its selection
/// and then its text, before anything is drawn. Anything else that sets the draft goes through
/// `replace(_:with:)`. An index read in a different string is invalid: Swift returns nil for
/// one past the end of an ASCII string, but traps on one from the field's UTF-16 text past the
/// end of a native string with any other character, such as autocorrect's curly apostrophe.
@Observable
final class Caret {
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

    /// Sets `draft` to `text` from outside the field, with the caret at its end, where the field
    /// puts its own when its text is replaced.
    func replace(_ draft: inout String, with text: String) {
        draft = text
        selection = TextSelection(insertionPoint: draft.endIndex)
    }
}

/// The `_`: blinking from the moment editing starts or the caret moves, still at rest, and
/// breathing in blue at rest while a new placeholder arrives.
private struct TitleCursor: View {
    let caret: Caret
    let draft: String
    let placeholder: String
    /// How many cells fit across the title, which the `_` wraps the text at; nil, and no `_`,
    /// until it is measured.
    let columns: Int?
    let isEditing: Bool
    /// How far toward the joining blue the `_` at rest is, and how deeply it breathes.
    let tint: Double
    let blinks: Bool

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
            if isEditing, blinks {
                TimelineView(.periodic(from: since, by: Self.blinkInterval)) { context in
                    let ticks = context.date.timeIntervalSince(since) / Self.blinkInterval
                    let isOn = Int(ticks.rounded()).isMultiple(of: 2)
                    underscore(isOn ? .pp(.textPrimary) : .clear)
                }
            } else if tint > 0, !isEditing, blinks {
                // The breath deepens and fades with the tint, so the `_` eases back to rest.
                TimelineView(.animation) { context in
                    underscore(restingColor)
                        .opacity(1 - (1 - Self.pulseOpacity(at: context.date)) * tint)
                }
            } else {
                underscore(isEditing ? .pp(.textPrimary) : restingColor)
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

    private var restingColor: Color {
        Color.pp(.borderStrong).mix(with: .pp(.railJoin), by: tint)
    }

    /// Full at the start of each pulse, fading smoothly to its lowest halfway through.
    private static func pulseOpacity(at date: Date) -> Double {
        let period = SuggestionTiming.pulsePeriod
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
            / period
        let lowest = SuggestionTiming.pulseLowestOpacity
        return lowest + (1 - lowest) * (1 + cos(2 * .pi * phase)) / 2
    }

    /// Where the cursor is in what the field shows, the draft or the placeholder, as a character
    /// offset: under the placeholder's first letter while editing, after the text at rest, and
    /// nowhere for a range selection.
    private var offset: Int? {
        if draft.isEmpty {
            return isEditing ? 0 : placeholder.count
        }
        guard isEditing else { return draft.count }
        return EditableTitle.insertionPoint(of: caret.selection, in: draft)
            .map { draft.distance(from: draft.startIndex, to: $0) }
    }

    /// One character cell of the title's monospaced font, measured over many characters and
    /// lines.
    private static func cell(in context: GraphicsContext) -> CGSize {
        let count = measuredCells
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
        let shown = draft.isEmpty ? placeholder : draft
        let offset = offset
        return Canvas { context, _ in
            guard let offset, let columns else { return }
            let mark = context.resolve(Text(verbatim: "_").foregroundStyle(color))
            let cell = Self.cell(in: context)
            let place = EditableTitle.cursorCell(at: offset, in: shown, columns: columns)
            let origin = CGPoint(
                x: CGFloat(place.column) * cell.width,
                y: CGFloat(place.line) * cell.height + drop,
            )
            context.draw(mark, at: origin, anchor: .topLeading)
        }
    }
}

#Preview("Editing") {
    @Previewable @State var caret = {
        let caret = Caret()
        let draft = "Arm and back"
        caret.selection = TextSelection(
            insertionPoint: draft.index(draft.startIndex, offsetBy: 9),
        )
        return caret
    }()
    EditableTitleContent(
        draft: .constant("Arm and back"),
        caret: caret,
        selection: .constant(caret.selection),
        placeholder: "New routine",
        shownPlaceholder: "New routine",
        isEditing: true,
        blinks: true,
        accessibilityLabel: "Routine name",
        accessibilityHint: "Renames the routine.",
        behavior: EmptyModifier(),
    )
    .padding()
    .background(Color.pp(.background))
}
