// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// The key at the bottom of a workout in each of its roles, as the routine screen labels it:
/// a capsule in the primary key's colors, its label semibold, and at AX5 a long name wrapping
/// inside the round ends rather than cut short. Where the bar puts it is
/// `ComponentSnapshotTests.oneExercise`'s, with Start.
@Suite("Workout key")
struct WorkoutKeySnapshotTests {
    private static let width: CGFloat = 390

    @Test("The workout's key: Log set, Log left, the way back to a long name, Finish workout")
    func roles() {
        let keys = VStack(spacing: Spacing.md) {
            Button("Log set") { }
            Button("Log left") { }
            Button(
                "Single-arm dumbbell Romanian deadlift to row",
                systemImage: "arrow.down",
            ) { }
            Button("Finish workout") { }
        }
        .buttonStyle(.primaryKey)
        .padding(Spacing.md)
        .background(Color.pp(.background))
        assertThemedSnapshots(of: keys, width: Self.width)
    }
}

#endif
