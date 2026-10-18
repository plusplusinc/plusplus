import SwiftUI

/// The title drawn from plain values: what the field holds, whether it is being edited, and how
/// the placeholder and the `_` look. `EditableTitle` feeds it and owns focus; snapshots render
/// it directly.
struct EditableTitleContent: View {
    @Binding var draft: String
    /// The field's focus; nil where nothing takes focus, as in a snapshot.
    var isFocused: Binding<Bool>?
    /// A selection to force, for a snapshot; nil leaves it to the text system.
    var selection: NSRange?
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
    let accessibilityLabel: LocalizedStringResource
    let accessibilityHint: LocalizedStringResource

    @ScaledMetric(relativeTo: ScreenTitle.textStyle) private var fontSize = ScreenTitle.size
    /// How far the `_` sits below the font's own underscore, so it reads as a cursor under the
    /// letter rather than a typed character: just past the tails of g, p, and y. Scaled with the
    /// title.
    @ScaledMetric(relativeTo: ScreenTitle.textStyle) private var drop: CGFloat = 4.5
    @ObserveHotReload private var hotReload

    var body: some View {
        // The breath runs on SwiftUI's clock, only while there is one.
        TimelineView(.animation(paused: !breathes)) { context in
            field(cursorOpacity: breathes ? 1 - (1 - Self.pulseOpacity(at: context.date)) *
                cursorTint : 1)
        }
        .hotReloadable()
    }

    @ViewBuilder
    private func field(cursorOpacity: Double) -> some View {
        #if os(iOS)
        TitleTextView(
            draft: $draft,
            isFocused: isFocused,
            isEditing: isEditing,
            selection: selection,
            fontSize: fontSize,
            drop: drop,
            textColor: .pp(.textPrimary),
            placeholder: String(shownPlaceholder.enumerated().map { standIns[$0] ?? $1 }),
            placeholderColors: (0 ..< shownPlaceholder.count).map { index in
                guard let tint = tints[index], tint > 0 else { return restingColor }
                return restingColor.mix(with: .pp(.railJoin), by: tint)
            },
            placeholderOpacity: placeholderOpacity,
            cursorColor: isEditing ? .pp(.textPrimary) : cursorRestingColor,
            cursorOpacity: cursorOpacity,
            blinks: blinks,
            accessibilityLabel: String(localized: accessibilityLabel),
            accessibilityHint: String(localized: accessibilityHint),
            accessibilityPlaceholder: placeholder,
        )
        #else
        Text(verbatim: draft.isEmpty ? shownPlaceholder : draft)
            .ppScreenTitleFont()
            .foregroundStyle(draft.isEmpty ? restingColor : .pp(.textPrimary))
        #endif
    }

    /// Whether the `_` at rest is breathing in blue, as a new placeholder arrives.
    private var breathes: Bool {
        cursorTint > 0 && !isEditing && blinks
    }

    /// White for a suggestion at rest, as a name is. Gray for the placeholder, and for a
    /// suggestion in a field emptied while editing, where it is only a hint at what ending with
    /// nothing brings back.
    private var restingColor: Color {
        .pp(isSuggested && !isEditing ? .textPrimary : .textSecondary)
    }

    private var cursorRestingColor: Color {
        Color.pp(.borderStrong).mix(with: .pp(.railJoin), by: cursorTint)
    }

    /// Full at the start of each pulse, fading smoothly to its lowest halfway through.
    private static func pulseOpacity(at date: Date) -> Double {
        let period = SuggestionTiming.pulsePeriod
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
            / period
        let lowest = SuggestionTiming.pulseLowestOpacity
        return lowest + (1 - lowest) * (1 + cos(2 * .pi * phase)) / 2
    }
}

#Preview("Editing") {
    EditableTitleContent(
        draft: .constant("Arm and back"),
        selection: NSRange(location: 9, length: 0),
        placeholder: "New routine",
        shownPlaceholder: "New routine",
        isEditing: true,
        blinks: true,
        accessibilityLabel: "Routine name",
        accessibilityHint: "Renames the routine.",
    )
    .padding()
    .background(Color.pp(.background))
}
