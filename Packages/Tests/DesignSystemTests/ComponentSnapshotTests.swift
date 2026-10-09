// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// The routine screen's content, built from components the way the app composes it. The screen
/// itself lives in the app, which has no test target; its toolbar is checked on the simulator.
@Suite("Components")
struct ComponentSnapshotTests {
    private static let screenWidth: CGFloat = 390

    private func content(name: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            EditableTitle(
                text: .constant(name),
                defaultText: "New routine",
                accessibilityLabel: "Routine name",
                accessibilityHint: "Renames the routine.",
            )
            Button("Add exercise", systemImage: "plus") { }
                .buttonStyle(.key)
        }
        .padding(Spacing.md)
        .background(Color.pp(.background))
    }

    @Test("A new routine: title at rest and Add exercise")
    func newRoutine() {
        assertThemedSnapshots(of: content(name: "New routine"), width: Self.screenWidth)
    }

    @Test("A long name wraps, and the cursor follows its last line")
    func longName() {
        assertThemedSnapshots(
            of: content(name: "Upper body strength and conditioning"),
            width: Self.screenWidth,
        )
    }
}

#endif
