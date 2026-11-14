// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import QuartzCore
import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// Where a swipe begun while the drawer settles starts from: how far open the drawer is drawn
/// (`DrawerSlide`). The swipe started from the settle's end, which the model holds from the
/// moment the settle starts, so a drawer caught as it slid shut jumped under the finger. Read
/// from a hosted view over the frames a settle plays on.
@MainActor
@Suite("Drawer slide")
struct DrawerSlideTests {
    @Observable
    final class Drawer {
        var progress: CGFloat = 1
    }

    private struct Host: View {
        let drawer: Drawer
        let drawn: DrawnProgress

        var body: some View {
            Color.clear
                .modifier(DrawerSlide(progress: drawer.progress, width: 324, drawn: drawn))
        }
    }

    /// What the drawer reads as drawn on every frame while the settle plays.
    private final class Frames: NSObject {
        let drawn: DrawnProgress
        private(set) var reads: [CGFloat] = []

        init(drawn: DrawnProgress) {
            self.drawn = drawn
        }

        @objc func frame(_: CADisplayLink) {
            reads.append(drawn.value)
        }
    }

    private static let duration = 0.4

    @Test("While a settle plays, the drawer reads as drawn partway, not at the settle's end")
    func readsTheDrawnProgressMidSettle() throws {
        let drawer = Drawer()
        let drawn = DrawnProgress(value: 0)
        let window = UIWindow.sceneless(
            hosting: UIHostingController(rootView: Host(drawer: drawer, drawn: drawn)),
            at: .large,
        )
        defer { window.isHidden = true }
        window.settle()
        #expect(drawn.value == 1, "Open at rest reads \(drawn.value)")

        let frames = Frames(drawn: drawn)
        let link = CADisplayLink(target: frames, selector: #selector(Frames.frame(_:)))
        link.add(to: .main, forMode: .common)
        defer { link.invalidate() }
        withAnimation(.linear(duration: Self.duration)) { drawer.progress = 0 }
        // Real time is what's tested: the frames the settle draws, until it lands or well past
        // its end.
        let deadline = Date.now.addingTimeInterval(Self.duration + 0.6)
        while Date.now < deadline, drawn.value > 0 {
            RunLoop.main.run(mode: .default, before: .now.addingTimeInterval(0.005))
        }

        let reads = frames.reads
        try #require(reads.count >= 4, "Only \(reads.count) frames shown")
        #expect(
            reads.contains { $0 > 0.1 && $0 < 0.9 },
            "A settle from 1 to 0 read, frame by frame, \(reads)",
        )
        #expect(drawn.value == 0, "Landed reads \(drawn.value)")
    }
}

#endif
