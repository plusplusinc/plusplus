import SwiftUI

/// The keys at the bottom while a timed set counts, in the key's place: its log key, "Log
/// early", wide, gray as a secondary key, filling with the done purple from its leading edge as
/// the set counts (`KeyFill`, `PrimaryKeyButtonStyle.countKey(filling:)`), and +15 s beside it
/// in the same quieter look, 8 pt apart. To the bar they are one more key, so they swap with
/// the others as any two keys do; while the bar has them out in a swap, a tap does nothing.
/// They stand on a plate of the screen's color, as `RestKeys` do. VoiceOver reads the log key
/// with the seconds done as its value ("12 of 30 seconds done"), updated each second only while
/// VoiceOver runs.
public struct TimedSetKeys: View {
    let logText: String
    let filling: KeyFill
    let isOut: Bool
    let onLog: () -> Void
    let onExtend: () -> Void

    /// +15 s's width at the default text size, as drawn.
    @ScaledMetric(relativeTo: .title3) private var extendWidth: CGFloat = 112
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    /// The moment VoiceOver's value is read for: now, as each whole second of the count comes.
    @State private var spokenAt = Date.now

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
            // Its value, the seconds done, follows the count each second only while VoiceOver
            // runs: no other reader needs it redrawn.
            logKey(at: voiceOver ? spokenAt : .now)
                .task(id: voiceOver && !filling.holds ? filling : nil) { await tick() }
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

    /// While VoiceOver runs, sets `spokenAt` now, then at each whole second of the count while
    /// it runs; paused or logged, the value reads the fill's own seconds. A task, as the
    /// bar's time key ticks (`WorkoutTimeKey`), not a `TimelineView`.
    private func tick() async {
        guard voiceOver, !filling.holds else { return }
        spokenAt = .now
        while true {
            let next = filling.ends.addingTimeInterval(
                spokenAt.timeIntervalSince(filling.ends).rounded(.down) + 1,
            )
            let wait = next.timeIntervalSinceNow
            if wait > 0 {
                guard await (try? Task.sleep(for: .seconds(wait), tolerance: .zero)) != nil
                else { return }
            }
            spokenAt = max(.now, next)
        }
    }

    /// "Log early", its value the seconds done at `date`.
    private func logKey(at date: Date) -> some View {
        Button {
            if !isOut {
                onLog()
            }
        } label: {
            Text(verbatim: logText)
        }
        .buttonStyle(.countKey(filling: filling))
        .accessibilityIdentifier("workout.key")
        .accessibilityValue(filling.spokenDone(at: date) ?? "")
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
