#if canImport(UIKit) && !os(watchOS)

    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import DesignSystem

    /// The contract these images guard: **the leading chevron occupies the same pixels whether one
    /// chevron is showing or three.** Rendered on a fixed-width ground so a layout regression moves
    /// ink rather than resizing the image, which a perceptual comparison would otherwise absorb.
    @Suite("Chevron run")
    @MainActor
    struct ChevronRunSnapshotTests {
        private static let width: CGFloat = 120

        private func ground(_ run: ChevronRun) -> some View {
            run
                .font(.ppButtonLabel)
                .foregroundStyle(Color.ppOnPrimary)
                .frame(width: Self.width, alignment: .leading)
                .padding(Spacing.sm)
                .background(Color.ppPrimaryFill)
        }

        private func assertRun(
            _ run: ChevronRun,
            named name: String,
            testName: String = #function
        ) {
            assertSnapshot(
                of: ground(run),
                as: .image(
                    precision: 0.99,
                    perceptualPrecision: 0.98,
                    layout: .fixed(width: Self.width + Spacing.sm * 2, height: 0)
                ),
                named: name,
                testName: testName
            )
        }

        @Test("At rest a single chevron shows, with the trio's width already reserved")
        func atRest() {
            assertRun(ChevronRun(isRunning: false, activeIndex: 0), named: "rest")
        }

        @Test("Running lights the leading chevron without moving it")
        func runningFirstLit() {
            assertRun(ChevronRun(isRunning: true, activeIndex: 0), named: "running-0")
        }

        @Test("The highlight reaches the trailing chevron")
        func runningLastLit() {
            assertRun(ChevronRun(isRunning: true, activeIndex: 2), named: "running-2")
        }
    }

#endif
