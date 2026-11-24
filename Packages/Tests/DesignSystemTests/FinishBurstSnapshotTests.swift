// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// The finish's "++" over Finish workout, held at the moment the two "+"s meet: green, SF Mono
/// bold at the title style, sitting on the key's top as the key bar places it, and at AX5 grown
/// with the text size without clipping. With Reduce Motion both stand at full size, in place.
/// How it moves over time is the recordings'.
@Suite("Finish burst")
struct FinishBurstSnapshotTests {
    private static let width: CGFloat = 390

    /// The burst on the key's top, as `primaryKeyBar` places it: as wide as the key, its
    /// bottom on the key's top edge.
    private func burst(reduceMotion: Bool) -> some View {
        VStack(spacing: 0) {
            FinishBurst(heldAt: FinishBurst.met, reduceMotion: reduceMotion)
            Button("Finish workout") { }
                .buttonStyle(.primaryKey)
        }
        .padding(.top, Spacing.xl)
        .padding(Spacing.md)
        .background(Color.pp(.background))
    }

    @Test("The finish's ++ over the key, the two + meeting")
    func meeting() {
        assertThemedSnapshots(of: burst(reduceMotion: false), width: Self.width)
    }

    @Test("With Reduce Motion, the finish's ++ stands in place at full size")
    func reduceMotion() {
        assertThemedSnapshots(of: burst(reduceMotion: true), width: Self.width)
    }
}

#endif
