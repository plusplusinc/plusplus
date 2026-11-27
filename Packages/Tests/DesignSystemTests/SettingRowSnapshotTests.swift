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
            SettingRow(
                "Sync workouts",
                value: "Off",
                isOn: false,
                change: .init("Sync to Apple Health", leavesApp: false) { },
            )
            SettingRow(
                "Sync workouts",
                value: "On",
                isOn: true,
                change: .init(
                    "Manage in Apple Health",
                    leavesApp: true,
                    note: "Tap your picture",
                ) { },
            )
            SettingRow(
                "Sync workouts",
                value: "Off",
                isOn: false,
                change: .init(
                    "Turn on in Apple Health",
                    leavesApp: true,
                    note: "Tap your picture",
                ) { },
            )
        }
        .padding(Spacing.md)
        .sheetGround()
        assertThemedSnapshots(of: view, width: Self.width)
    }
}

#endif
