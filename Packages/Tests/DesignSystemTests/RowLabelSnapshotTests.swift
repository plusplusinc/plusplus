// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// Rows as the exercise picker shows them: no rail, the system list's insets around each.
@Suite("Row label")
struct RowLabelSnapshotTests {
    @Test("Picker rows: equipment line, two equipment, bodyweight, long name")
    func pickerRows() {
        let rows = VStack(alignment: .leading, spacing: Spacing.md) {
            RowLabel(title: "Goblet squat", detail: "Kettlebell")
            RowLabel(title: "Dumbbell bench press", detail: "Dumbbells, bench")
            RowLabel(title: "Push-up", detail: nil)
            RowLabel(title: "Cross-body shoulder stretch", detail: nil)
            RowLabel(title: "Bulgarian split squat", detail: "Dumbbells, bench")
        }
        .padding(Spacing.md)
        .background(Color.pp(.background))
        assertThemedSnapshots(of: rows, width: 390)
    }
}

#endif
