// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// A name growing from a row's size into the current exercise's, drawn at rest, halfway, and
/// grown.
@Suite("Growing name")
struct GrowingNameSnapshotTests {
    private func stages(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            ForEach([CGFloat(0), 0.5, 1], id: \.self) { growth in
                GrowingName(title: title, growth: growth)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pp(.background))
    }

    @Test("A long name halfway: crossfades where its sizes break apart, not where alike (AX5)")
    func wrapsDifferently() {
        assertThemedSnapshots(of: stages("Single-leg Romanian deadlift"), width: 320)
    }
}

#endif
