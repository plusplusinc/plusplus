import SwiftUI

/// A count's keys at the bottom, in the key's place, a timed set's and a rest's alike: a wide
/// key, gray as a secondary key, filling with the done purple from its leading edge as the count
/// runs (`KeyFill`, `PrimaryKeyButtonStyle.countKey(filling:)`), and +15 s beside it in the same
/// quieter look, 8 pt apart. On a timed set the wide key is "Log early"; in a rest, "Skip rest".
/// To the bar they are one more key, so they swap with the others as any two keys do; while the
/// bar has them out in a swap, a tap does nothing. They stand on a plate of the screen's color in
/// the one key's shape, so no row shows between them. VoiceOver reads the wide key with the
/// count as its value (`Spoken`), updated each second only while VoiceOver runs, and +15 s as
/// "Plus 15 seconds".
public struct CountKeys: View {
    /// What VoiceOver reads as the wide key's value.
    public enum Spoken: Sendable {
        /// "12 of 30 seconds done": what a tap on "Log early" logs.
        case done
        /// "35 seconds left": what a tap on "Skip rest" skips.
        case left
    }

    let text: String
    let filling: KeyFill
    let spoken: Spoken
    let isOut: Bool
    let onKey: () -> Void
    let onExtend: () -> Void

    /// +15 s's width at the default text size, as drawn.
    @ScaledMetric(relativeTo: .title3) private var extendWidth: CGFloat = 112
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.locale) private var locale

    public init(
        text: String,
        filling: KeyFill,
        spoken: Spoken = .done,
        isOut: Bool = false,
        onKey: @escaping () -> Void,
        onExtend: @escaping () -> Void,
    ) {
        self.text = text
        self.filling = filling
        self.spoken = spoken
        self.isOut = isOut
        self.onKey = onKey
        self.onExtend = onExtend
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            // Its value follows the count each second only while VoiceOver runs: no other
            // reader needs it redrawn.
            if voiceOver {
                TimelineView(.periodic(from: filling.ends, by: 1)) { context in
                    wideKey(at: context.date)
                }
            } else {
                wideKey(at: .now)
            }
            Button {
                if !isOut {
                    onExtend()
                }
            } label: {
                Text(AttributedString.monoNumbers("+15 s", font: .ppPrimaryKeyNumber))
            }
            .buttonStyle(.secondaryKey)
            // At the accessibility sizes its scaled width left the wide key a letter wide, its
            // words stacked: there it takes only its own words' room.
            .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : extendWidth)
            .fixedSize(horizontal: dynamicTypeSize.isAccessibilitySize, vertical: false)
            .accessibilityLabel("Plus 15 seconds")
        }
        // On a plate of the screen's own color, the one key's footprint, so the rows running on
        // under the bar show no more between the two keys than around the one: through the gap,
        // a row's words were readable.
        .background(Capsule().fill(.pp(.background)))
    }

    /// The wide key, its value the count at `date`.
    private func wideKey(at date: Date) -> some View {
        Button {
            if !isOut {
                onKey()
            }
        } label: {
            Text(verbatim: text)
        }
        .buttonStyle(.countKey(filling: filling))
        .accessibilityIdentifier("workout.key")
        .accessibilityValue(value(at: date) ?? "")
    }

    private func value(at date: Date) -> String? {
        switch spoken {
        case .done: filling.spokenDone(at: date)
        case .left: filling.spokenLeft(at: date, locale: locale)
        }
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        CountKeys(
            text: "Log early",
            filling: KeyFill(length: 30, ends: .now.addingTimeInterval(20)),
            onKey: { },
            onExtend: { },
        )
        CountKeys(
            text: "Skip rest",
            filling: KeyFill(length: 90, ends: .now, pausedLeft: 40),
            spoken: .left,
            onKey: { },
            onExtend: { },
        )
    }
    .padding()
    .background(Color.pp(.background))
}
