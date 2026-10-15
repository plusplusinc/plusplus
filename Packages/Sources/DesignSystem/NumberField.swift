import SwiftUI

/// A stepper's number that can be typed: tap it and a number pad rises, the number gives way
/// to what is typed with the `_` after it and a line under the slot, and when typing ends the
/// typed text is handed to `onCommit`, if anything was typed.
///
/// Its own `_`, not the system caret: a number's caret is always at its end, and what is drawn
/// isn't always what was typed (a time's 1, 3, 0 draws "1:30"). So a clear `TextField` laid over
/// the drawing takes the taps, focus, and keys, and `NumberFieldContent` draws from plain
/// values, as `EditableTitleContent` does for the title.
public struct NumberField<Focus: Hashable>: View {
    private let value: String?
    private let unit: String?
    private let typingUnit: String?
    private let typesDecimal: Bool
    private let accessibilityLabel: String
    private let focus: FocusState<Focus?>.Binding
    private let id: Focus
    private let filter: (String) -> String
    private let typedText: (String) -> String
    private let onCommit: (String) -> Void

    /// The typed text, filtered as it changes.
    @State private var raw = ""
    /// Whether anything was typed since typing started: tapping in and out changes nothing.
    @State private var isEdited = false
    @ObserveHotReload private var hotReload

    /// - Parameters:
    ///   - value: The number at rest, or nil for "Not set".
    ///   - unit: Drawn small after the number at rest.
    ///   - typingUnit: Drawn after what is typed.
    ///   - filter: What the field keeps of the typed text.
    ///   - typedText: How the kept text reads while typing.
    public init(
        value: String?,
        unit: String?,
        typingUnit: String?,
        typesDecimal: Bool,
        accessibilityLabel: String,
        focus: FocusState<Focus?>.Binding,
        id: Focus,
        filter: @escaping (String) -> String,
        typedText: @escaping (String) -> String,
        onCommit: @escaping (String) -> Void,
    ) {
        self.value = value
        self.unit = unit
        self.typingUnit = typingUnit
        self.typesDecimal = typesDecimal
        self.accessibilityLabel = accessibilityLabel
        self.focus = focus
        self.id = id
        self.filter = filter
        self.typedText = typedText
        self.onCommit = onCommit
    }

    public var body: some View {
        let isEditing = focus.wrappedValue == id
        NumberFieldContent(
            text: isEditing ? typedText(raw) : value,
            unit: isEditing ? typingUnit : unit,
            isEditing: isEditing,
            blinks: true,
        )
        .overlay {
            // No placeholder: the drawing shows "Not set" itself.
            TextField(String(), text: $raw)
                #if os(iOS)
                .keyboardType(typesDecimal ? .decimalPad : .numberPad)
                #endif
                .focused(focus, equals: id)
                .foregroundStyle(.clear)
                .tint(.clear)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(isEditing ? typedText(raw) : (value ?? "Not set"))
        }
        .onChange(of: raw) { _, typed in
            let kept = filter(typed)
            if kept != typed {
                raw = kept
            }
            if isEditing {
                isEdited = true
            }
        }
        .onChange(of: isEditing) { _, isEditing in
            if !isEditing, isEdited {
                onCommit(raw)
            }
            isEdited = false
            raw = ""
        }
        // A sheet swiped away while typing can take the field with it before focus clears.
        .onDisappear {
            if isEdited {
                onCommit(raw)
            }
        }
        .hotReloadable()
    }
}

/// The number drawn from plain values: at rest the value and its unit, or "Not set"; while
/// typing, the typed text with the `_` after it, and a line under the slot.
struct NumberFieldContent: View {
    /// Nil or empty at rest reads "Not set"; empty while typing shows the `_` alone.
    let text: String?
    let unit: String?
    let isEditing: Bool
    /// Whether the `_` blinks while typing. Snapshots hold it lit.
    let blinks: Bool

    @ObserveHotReload private var hotReload

    var body: some View {
        let text = text ?? ""
        Group {
            if text.isEmpty, !isEditing {
                Text("Not set")
                    .font(.ppValuePlaceholder)
                    .foregroundStyle(.pp(.textSecondary))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(verbatim: text)
                            .foregroundStyle(.pp(.textPrimary))
                        if isEditing {
                            NumberCursor(blinks: blinks)
                        }
                    }
                    .ppValueFont()
                    if let unit {
                        Text(unit)
                            .font(.ppValueUnit)
                            .foregroundStyle(.pp(.textSecondary))
                    }
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity, minHeight: Spacing.xl + Spacing.md)
        .overlay(alignment: .bottom) {
            if isEditing {
                Rectangle()
                    .fill(.pp(.textPrimary))
                    .frame(height: 2)
            }
        }
        .hotReloadable()
    }
}

/// The `_` after a typed number, blinking as the title's does.
private struct NumberCursor: View {
    let blinks: Bool

    @State private var since = Date.now
    @ObserveHotReload private var hotReload

    var body: some View {
        Group {
            if blinks {
                TimelineView(.periodic(from: since, by: CursorBlink.interval)) { context in
                    underscore(isOn: CursorBlink.isOn(since: since, at: context.date))
                }
            } else {
                underscore(isOn: true)
            }
        }
        .accessibilityHidden(true)
        .hotReloadable()
    }

    private func underscore(isOn: Bool) -> some View {
        Text(verbatim: "_").foregroundStyle(isOn ? .pp(.textPrimary) : .clear)
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        NumberFieldContent(text: "135", unit: "lb", isEditing: false, blinks: false)
        NumberFieldContent(text: nil, unit: nil, isEditing: false, blinks: false)
        NumberFieldContent(text: "142.5", unit: "lb", isEditing: true, blinks: true)
        NumberFieldContent(text: "1:30", unit: nil, isEditing: true, blinks: true)
    }
    .frame(width: 126)
    .padding()
    .background(Color.pp(.background))
}

/// How a drawn `_` blinks while typing: the 1.06 s cycle of a text cursor, on half, off half,
/// no fade, counted from when typing started or the caret last moved.
enum CursorBlink {
    static let interval: TimeInterval = 0.53

    static func isOn(since start: Date, at date: Date) -> Bool {
        Int((date.timeIntervalSince(start) / interval).rounded()).isMultiple(of: 2)
    }
}
