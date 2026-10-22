// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// The workout time key's label: its icon on the digits' baseline, white while running and gray
/// while paused. The glass key around it is the system's bar item, seen on the simulator.
@Suite("Workout time label")
struct WorkoutTimeLabelSnapshotTests {
    private static let width: CGFloat = 400

    private func label(_ text: String, isPaused: Bool) -> some View {
        WorkoutTimeLabel(text, isPaused: isPaused)
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.pp(.background))
    }

    @Test("Running: pause and the time in white")
    func running() {
        assertThemedSnapshots(of: label("04:12", isPaused: false), width: Self.width)
    }

    @Test("Paused: play in white and the time in gray, at the running label's width")
    func paused() {
        assertThemedSnapshots(of: label("04:12", isPaused: true), width: Self.width)
    }

    @Test("Past an hour, the time grows to h:mm:ss")
    func pastAnHour() {
        assertThemedSnapshots(of: label("1:04:12", isPaused: false), width: Self.width)
    }
}

#endif
