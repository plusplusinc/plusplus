import SwiftUI

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
    /// Below 1 while the old placeholder fades out for a new one.
    let placeholderOpacity: Double
    /// The character of `shownPlaceholder` typing in, drawn in the rail's joining blue.
    let joiningIndex: Int?
    /// A stand-in letter drawn in the joining character's place while it decodes.
    let decodeGlyph: Character?
    /// Whether the `_` pulses at rest, in the rail's joining blue, while a new placeholder is on
    /// its way and typing in.
    let pulses: Bool
    let isEditing: Bool
    /// Whether the `_` blinks while editing, and pulses at rest. Snapshots hold it lit, however
    /// long after the view was made they render.
    let blinks: Bool
    let accessibilityLabel: LocalizedStringKey
    let accessibilityHint: LocalizedStringKey
    /// What the field does with focus, Return, and pasted lines: the wrapper's.
    let behavior: Behavior

    /// The placeholder's height where it is drawn, wrapped, in place of an empty field.
    @State private var placeholderHeight: CGFloat = 0
    /// The height of one line of the title.
    @State private var lineHeight: CGFloat = 0
    @ObserveHotReload private var hotReload

    var body: some View {
        ZStack(alignment: .topLeading) {
            // A field's own placeholder stays on one line, truncated, so the placeholder is drawn
            // here, wrapping like the text it stands for.
            if draft.isEmpty {
                Text(drawnPlaceholder)
                    .foregroundStyle(.pp(.textSecondary))
                    .opacity(placeholderOpacity)
                    // With Reduce Motion a new placeholder crossfades in rather than typing.
                    .contentTransition(.opacity)
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) {
                        placeholderHeight = $0
                    }
                    .background {
                        Text(verbatim: "_")
                            .hidden()
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) {
                                lineHeight = $0
                            }
                    }
            }
            // An empty field is one line tall, and VoiceOver frames the field, so it reserves
            // as many lines as the placeholder drawn in its place. A frame around the field
            // would not do: the field stays as tall as its lines inside any frame.
            field
                .lineLimit(
                    draft.isEmpty
                        ? EditableTitle.lineCount(
                            height: placeholderHeight,
                            lineHeight: lineHeight,
                        )...
                        : 1...,
                )
        }
        .overlay(alignment: .top) {
            TitleCursor(
                caret: caret,
                draft: draft,
                placeholder: shownPlaceholder,
                isEditing: isEditing,
                pulses: pulses,
                blinks: blinks,
            )
        }
        .ppScreenTitleFont()
        .hotReloadable()
    }

    /// The placeholder as drawn: the joining character blue, as its stand-in while it decodes.
    private var drawnPlaceholder: AttributedString {
        let characters = Array(shownPlaceholder)
        guard let index = joiningIndex, characters.indices.contains(index) else {
            return AttributedString(shownPlaceholder)
        }
        var joining = AttributedString(String(decodeGlyph ?? characters[index]))
        joining.foregroundColor = Color.pp(.railJoin)
        return AttributedString(String(characters[..<index])) + joining
            + AttributedString(String(characters[(index + 1)...]))
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
}

/// The `_`: blinking from the moment editing starts or the caret moves, still at rest, and
/// pulsing at rest while a new placeholder is on its way.
private struct TitleCursor: View {
    let caret: Caret
    let draft: String
    let placeholder: String
    let isEditing: Bool
    let pulses: Bool
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
            } else if pulses, !isEditing, blinks {
                TimelineView(.animation) { context in
                    underscore(.pp(.railJoin))
                        .opacity(Self.pulseOpacity(at: context.date))
                }
            } else {
                underscore(isEditing ? .pp(.textPrimary) : .pp(.borderStrong))
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
        let shown = draft.isEmpty ? placeholder : draft
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
        placeholderOpacity: 1,
        joiningIndex: nil,
        decodeGlyph: nil,
        pulses: false,
        isEditing: true,
        blinks: true,
        accessibilityLabel: "Routine name",
        accessibilityHint: "Renames the routine.",
        behavior: EmptyModifier(),
    )
    .padding()
    .background(Color.pp(.background))
}
