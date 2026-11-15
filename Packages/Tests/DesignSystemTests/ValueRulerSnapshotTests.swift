// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// The ruler under an open row's keys, alone and in its row, at a value off the labels so the
/// line's place reads against the ticks either side. At AX5 the labels grow, and so does the
/// room between ticks, so the label under the line is the value's.
@Suite("Value ruler")
struct ValueRulerSnapshotTests {
    private static let width: CGFloat = 390

    private static func timeLabel(_ seconds: Double) -> String {
        Duration.seconds(seconds)
            .formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
    }

    private static func timeRuler(_ seconds: Double, range: ClosedRange<Double>) -> ValueRuler {
        ValueRuler(
            value: seconds,
            range: range,
            tick: 5,
            medium: 15,
            major: 30,
            spacing: 10,
            label: timeLabel,
            onChange: { _ in },
        )
    }

    /// A weight's ruler at 27.5 lb, a tick each 0.5, labeled each 5; a time's at 45 s and a
    /// rest's at 1m 30s, a tick each 5 s, labeled each 30 s. The line sits on the value's tick,
    /// and at AX5 the labels, larger, keep apart.
    @Test("Rulers for a weight, a time, and a rest, the line on each value's tick")
    func rulers() {
        assertThemedSnapshots(
            of: VStack(spacing: Spacing.md) {
                ValueRuler(value: 27.5, range: 5 ... 1000) { _ in }
                Self.timeRuler(45, range: 5 ... 5995)
                Self.timeRuler(90, range: 0 ... 600)
            }
            .background(Color.pp(.surface)),
            width: Self.width,
        )
    }

    private static func row(
        _ label: String,
        value: String,
        number: Double,
        ruler: ValueRuler,
        isAutoRest: Bool = false,
    ) -> some View {
        let auto: Void? = isAutoRest ? () : nil
        return ValueRow(
            label: label,
            note: auto.map { "After each set" },
            value: value,
            number: number,
            tag: auto.map { "Auto" },
            showsTag: isAutoRest,
            spokenValue: value,
            isOpen: true,
            canDecrease: true,
            canIncrease: true,
            onToggle: { },
            onStep: { _ in },
            ruler: ruler,
            accessory: auto.map {
                Toggle("Auto", isOn: .constant(true))
                    .font(.ppRowTitle)
                    .foregroundStyle(.pp(.textPrimary))
                    .padding(.trailing, Spacing.xxs)
            },
            footer: auto.map {
                Text("Auto rest follows your reps and the exercise. Heavier sets rest longer.")
            },
        )
    }

    /// Open rows as the exercise sheet shows them: the weight with one decimal, a timed set's
    /// time and a rest with both their units, the rest tagged Auto with its switch and footer.
    @Test("Open rows with a ruler: weight, time, and rest with Auto")
    func openRows() {
        assertThemedSnapshots(
            of: VStack(spacing: Spacing.sm) {
                Self.row(
                    "Weight",
                    value: "27.5\u{00A0}lb/side",
                    number: 27.5,
                    ruler: ValueRuler(value: 27.5, range: 5 ... 1000) { _ in },
                )
                Self.row(
                    "Time",
                    value: "0m\u{00A0}45s",
                    number: 45,
                    ruler: Self.timeRuler(45, range: 5 ... 5995),
                )
                Self.row(
                    "Rest",
                    value: "1m\u{00A0}30s",
                    number: 90,
                    ruler: Self.timeRuler(90, range: 0 ... 600),
                    isAutoRest: true,
                )
            }
            .padding(Spacing.md)
            .background(Color.pp(.background)),
            width: Self.width,
        )
    }
}

#endif
