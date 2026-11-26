// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// Apple Health's row in Settings, as the sheet draws it on its ground: never asked, a button
/// reading Off; answered, plain text reading On or Off at full strength, never dimmed.
@Suite("Setting row snapshots")
struct SettingRowSnapshotTests {
    private static let width: CGFloat = 390

    @Test("Never asked, on, and off, each on its card")
    func states() {
        let view = VStack(spacing: Spacing.md) {
            SettingRow("Save workouts", value: "Off", hint: "Asks to save workouts") { }
            SettingRow("Save workouts", value: "On")
            SettingRow("Save workouts", value: "Off")
        }
        .padding(Spacing.md)
        .sheetGround()
        assertThemedSnapshots(of: view, width: Self.width)
    }
}

#endif
