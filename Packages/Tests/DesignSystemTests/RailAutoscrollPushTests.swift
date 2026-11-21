// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import OSLog
import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// A list pushed onto a navigation stack, under a bar and over a bottom `safeAreaBar` as the
/// workout screen is from Workouts, is laid out several times in the push's first frame
/// (`ScrollExtent`); its rail autoscroll reacts once a frame all the same, with no
/// `OnScrollGeometryChange` fault in the process's own log.
@MainActor
@Suite("Rail autoscroll on a push")
struct RailAutoscrollPushTests {
    @Observable
    final class Stack {
        var path: [Int] = []
        @ObservationIgnored var isPushedShown = false
    }

    private struct Pushed: View {
        let stack: Stack
        @State private var position = ScrollPosition()

        var body: some View {
            ScrollView {
                Text("Row").frame(maxWidth: .infinity, minHeight: 200)
            }
            .scrollPosition($position)
            .railAutoscroll($position)
            .safeAreaBar(edge: .bottom) {
                Color.gray.frame(height: 70)
            }
            .navigationTitle("Pushed")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { stack.isPushedShown = true }
        }
    }

    private struct Host: View {
        @Bindable var stack: Stack

        var body: some View {
            NavigationStack(path: $stack.path) {
                Text("Root")
                    .navigationDestination(for: Int.self) { _ in Pushed(stack: stack) }
            }
        }
    }

    @Test("A pushed list reacts to its scroll geometry once a frame")
    func oncePerFrameOnPush() throws {
        let stack = Stack()
        let window = UIWindow.sceneless(
            hosting: UIHostingController(rootView: Host(stack: stack)),
            at: .large,
        )
        defer { window.isHidden = true }
        window.settle()
        let start = Date.now
        stack.path = [1]
        let deadline = Date.now.addingTimeInterval(2)
        while !stack.isPushedShown, Date.now < deadline {
            RunLoop.main.run(mode: .default, before: .now.addingTimeInterval(0.005))
        }
        try #require(stack.isPushedShown, "the pushed list never appeared")
        // The push's first frames, where its bars are laid out.
        window.settle()

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let faults = try store.getEntries(
            at: store.position(date: start),
            matching: NSPredicate(
                format: "subsystem == %@ AND composedMessage CONTAINS %@",
                "com.apple.SwiftUI",
                "OnScrollGeometryChange",
            ),
        )
        .map(\.composedMessage)
        #expect(faults.isEmpty, "SwiftUI logged \(faults)")
    }
}

#endif
