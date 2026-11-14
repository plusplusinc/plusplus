// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

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

    private static let duration = 0.4

    @Test("Halfway through a settle, the drawer reads as drawn partway, not at the settle's end")
    func readsTheDrawnProgressMidSettle() {
        let drawer = Drawer()
        let drawn = DrawnProgress()
        let window = UIWindow.sceneless(
            hosting: UIHostingController(rootView: Host(drawer: drawer, drawn: drawn)),
            at: .large,
        )
        defer { window.isHidden = true }
        window.settle()
        #expect(drawn.value == 1, "Open at rest reads \(drawn.value)")

        withAnimation(.linear(duration: Self.duration)) { drawer.progress = 0 }
        // Real time is what's tested: the frames the settle draws until about halfway.
        let halfway = Date.now.addingTimeInterval(Self.duration / 2)
        while Date.now < halfway {
            RunLoop.main.run(mode: .default, before: .now.addingTimeInterval(0.005))
        }

        #expect(
            drawn.value > 0.2 && drawn.value < 0.8,
            "Halfway through a settle from 1 to 0, reads \(drawn.value)",
        )
    }
}

#endif
