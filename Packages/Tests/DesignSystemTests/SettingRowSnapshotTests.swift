// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// Apple Health's card in Settings, as the sheet draws it on its ground: never asked, Off and a
/// green button; on, a check and a neutral button that opens Apple Health, with where to go
/// there; off after a Don't Allow, the same in green; and the line alone where the Health app
/// can't be opened. At AX5 the line's no-break spaces must still wrap inside the card.
@Suite("Setting row snapshots")
struct SettingRowSnapshotTests {
    private static let width: CGFloat = 390
    private static let stops = "then Privacy\u{A0}›\u{A0}Apps\u{A0}›\u{A0}PlusPlus"

    @Test("Never asked, on, off, and off with no way to open Apple Health, each on its card")
    func states() {
        let path = "Tap your picture,\u{A0}\(Self.stops)"
        let view = VStack(spacing: Spacing.md) {
            SettingRow(
                "Sync workouts",
                value: "Off",
                isOn: false,
                change: .init("Sync to Apple Health") { },
            )
            SettingRow(
                "Sync workouts",
                value: "On",
                isOn: true,
                change: .init("Manage in Apple Health", opens: "Apple Health", note: path) { },
            )
            SettingRow(
                "Sync workouts",
                value: "Off",
                isOn: false,
                change: .init("Enable in Apple Health", opens: "Apple Health", note: path) { },
            )
            SettingRow(
                "Sync workouts",
                value: "Off",
                isOn: false,
                change: .directions("In Apple Health, tap your picture,\u{A0}\(Self.stops)"),
            )
        }
        .padding(Spacing.md)
        .sheetGround()
        assertThemedSnapshots(of: view, width: Self.width)
    }
}

#endif
