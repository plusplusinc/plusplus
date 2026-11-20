import SwiftUI

/// The keys at the bottom while a timed set counts, in the key's place: its log key, "Log
/// early", wide, gray as a secondary key, filling with the done purple from its leading edge as
/// the set counts (`KeyFill`, `PrimaryKeyButtonStyle.countKey(filling:)`), and +15 s beside it
/// in the same quieter look, 8 pt apart. Another key to the bar, so the log key
/// and they swap as any two keys do. While the bar has them out in a swap, a tap does nothing.
/// They stand on a plate of the screen's color, as `RestKeys` do.
public struct TimedSetKeys: View {
    let logText: String
    let filling: KeyFill
    let isOut: Bool
    let onLog: () -> Void
    let onExtend: () -> Void

    /// +15 s's width at the default text size, as drawn.
    @ScaledMetric(relativeTo: .title3) private var extendWidth: CGFloat = 112
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        logText: String,
        filling: KeyFill,
        isOut: Bool = false,
        onLog: @escaping () -> Void,
        onExtend: @escaping () -> Void,
    ) {
        self.logText = logText
        self.filling = filling
        self.isOut = isOut
        self.onLog = onLog
        self.onExtend = onExtend
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                if !isOut {
                    onLog()
                }
            } label: {
                Text(verbatim: logText)
            }
            .buttonStyle(.countKey(filling: filling))
            .accessibilityIdentifier("workout.key")
            Button {
                if !isOut {
                    onExtend()
                }
            } label: {
                Text(AttributedString.monoNumbers("+15 s", font: .ppPrimaryKeyNumber))
            }
            .buttonStyle(.secondaryKey)
            // At the accessibility sizes its scaled width left the log key a letter wide, its
            // words stacked: there it takes only its own words' room.
            .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : extendWidth)
            .fixedSize(horizontal: dynamicTypeSize.isAccessibilitySize, vertical: false)
            .accessibilityLabel("Plus 15 seconds")
        }
        .background(Capsule().fill(.pp(.background)))
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        TimedSetKeys(
            logText: "Log early",
            filling: KeyFill(length: 30, ends: .now.addingTimeInterval(20)),
            onLog: { },
            onExtend: { },
        )
        TimedSetKeys(
            logText: "Log early",
            filling: KeyFill(length: 30, ends: .now, pausedLeft: 2),
            onLog: { },
            onExtend: { },
        )
    }
    .padding()
    .background(Color.pp(.background))
}
