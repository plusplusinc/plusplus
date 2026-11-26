// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// Log's one-time Apple Health card on the screen's ground: the title and its line, the neutral
/// pill and the plain way out side by side, stacked at AX5 with no word broken.
@Suite("Offer card snapshots")
struct OfferCardSnapshotTests {
    @Test("Log's Apple Health card, its two buttons beside each other, stacked at AX5")
    func healthCard() {
        let view = OfferCard(
            "Save your workouts to Apple Health",
            line: "Each workout you finish, with its type and how long it took.",
            offer: "Save to Apple Health",
            dismiss: "Not now",
            take: { },
            decline: { },
        )
        .padding(Spacing.md)
        .background(Color.pp(.background))
        assertThemedSnapshots(of: view, width: 390)
    }
}

#endif
