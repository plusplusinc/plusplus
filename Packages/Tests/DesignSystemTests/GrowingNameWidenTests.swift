// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// A list laid out narrow and then at its width, as the app's window is in its first two frames
/// at launch: a row's name, its lines last read at the narrow width (`GrowingName.LineBreaks`),
/// is laid out at the new width at the height it keeps, so the list's scroll geometry reports
/// one content height there, not a stale one and then the right one in the same frame. Two in a
/// frame, the routine screen's reactions to its `ScrollExtent` were called twice and SwiftUI
/// logged an `OnScrollGeometryChange` fault; hosted here, it reports the two heights but logs no
/// fault, so the heights are what this checks.
@MainActor
@Suite("Growing name in a widening list")
struct GrowingNameWidenTests {
    @Observable
    final class Width {
        var value: CGFloat = 100
    }

    /// Each width and content height the list's scroll geometry was read at, in order.
    final class Readings {
        var seen: [CGSize] = []
    }

    private struct List: View {
        let width: Width
        let readings: Readings

        var body: some View {
            ScrollView {
                RowLabel(title: "Barbell bench press", detail: "3 × 8")
                    .padding(.horizontal)
            }
            .onScrollGeometryChange(
                for: ScrollExtent.self,
                of: { geometry in
                    readings.seen.append(geometry.contentSize)
                    return ScrollExtent(geometry)
                },
                action: { _, _ in },
            )
            .frame(width: width.value, height: width.value)
        }
    }

    @Test("A list's name laid out narrow, then wide, has one height at each width")
    func oneHeightAtEachWidth() throws {
        let width = Width()
        let readings = Readings()
        let window = UIWindow.sceneless(
            hosting: UIHostingController(rootView: List(width: width, readings: readings)),
            at: .large,
        )
        defer { window.isHidden = true }
        window.settle()
        let narrow = try #require(readings.seen.last)
        width.value = 402
        window.settle()

        let wide = readings.seen.filter { $0.width == 402 }
        try #require(!wide.isEmpty, "the list was never read at its width")
        #expect(wide.last?.height ?? 0 < narrow.height, "the name took no fewer lines")
        #expect(
            Set(wide.map(\.height)).count == 1,
            "At its width the list was read at \(wide.map(\.height))",
        )
    }
}

#endif
