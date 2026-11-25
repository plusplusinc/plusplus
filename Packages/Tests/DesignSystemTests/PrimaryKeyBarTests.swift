// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// The primary key's bar measures the screen's bottom safe area for its sides, which it learns
/// only after its first layout. If the bar's height followed that measurement, the bar would
/// change the list's inset in the frame after the list was first laid out, and SwiftUI updated
/// the list's scroll geometry twice in one frame, which it logs as an `OnScrollGeometryChange`
/// fault at every launch. The fault doesn't show in a hosted view, so this watches its cause:
/// the room the bar takes from the list, which has to be the same from the first layout on.
/// Serialized: a test that waits through a swap (`PrimaryKeyBarTests+Dip.swift`) gives up the
/// main actor, and another finishing then turned the accessibility tree off under it.
@MainActor
@Suite("Primary key bar", .serialized)
struct PrimaryKeyBarTests {
    /// The list's bottom safe area at each layout that changed it.
    private final class Insets {
        var seen: [CGFloat] = []
    }

    private struct Host: View {
        let insets: Insets

        var body: some View {
            ScrollView {
                Color.clear.frame(height: 2000)
            }
            .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.bottom) {
                insets.seen.append($0)
            }
            .primaryKeyBar(isPresented: true) {
                Button("Start") { }
            }
        }
    }

    /// In a window with a home indicator's safe area below, as the sceneless one has.
    @Test("The bar takes the same room from the list from its first layout")
    func roomHoldsFromFirstLayout() throws {
        let insets = Insets()
        let host = UIHostingController(rootView: Host(insets: insets))
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.settle()
        let first = try #require(insets.seen.first, "the list was never laid out")
        #expect(first > window.safeAreaInsets.bottom, "the bar took no room from the list")
        #expect(insets.seen == [first], "the bar's room changed after its first layout")
    }

    @Observable
    fileprivate final class Presence {
        var isPresented = true
    }

    private struct KeptRoomHost: View {
        let insets: Insets
        let presence: Presence

        var body: some View {
            ScrollView {
                Color.clear.frame(height: 2000)
            }
            .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.bottom) {
                insets.seen.append($0)
            }
            .primaryKeyBar(isPresented: presence.isPresented, keepsRoom: true) {
                Button("Start") { }
            }
        }
    }

    /// While the room is kept, the key goes and comes back, as through a set's "Start in",
    /// without the list under the bar moving: laid out at every frame of both moves.
    @Test("While the bar keeps its room, the list's room holds as the key goes and comes back")
    func keptRoomHoldsThroughArrival() async throws {
        let insets = Insets()
        let presence = Presence()
        let host = UIHostingController(rootView: KeptRoomHost(insets: insets, presence: presence))
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.settle()
        let first = try #require(insets.seen.first, "the list was never laid out")
        for isPresented in [false, true] {
            withAnimation(.easeInOut(duration: 0.3)) { presence.isPresented = isPresented }
            let end = ContinuousClock.now + .seconds(0.4)
            while ContinuousClock.now < end {
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(4))
            }
        }
        #expect(insets.seen == [first], "the list's room changed: \(insets.seen)")
    }

    /// Frames in the window, as laid out.
    private final class Frames {
        var key: CGRect?
        var floating: CGRect?
    }

    private struct FloatingHost: View {
        let isPresented: Bool
        let frames: Frames

        var body: some View {
            Color.clear
                .primaryKeyBar(isPresented: isPresented) {
                    Button("Start") { }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                            frames.key = $0
                        }
                } floating: {
                    Button("Add exercise", systemImage: "plus") { }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                            frames.floating = $0
                        }
                }
        }
    }

    private func frames(isPresented: Bool) throws -> (key: CGRect?, floating: CGRect) {
        let frames = Frames()
        let host = UIHostingController(
            rootView: FloatingHost(isPresented: isPresented, frames: frames),
        )
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.settle()
        return try (frames.key, #require(frames.floating, "the floating button was never laid out"))
    }

    /// The key sits where a tab bar floats, its ledge 21 pt above the screen's bottom and its
    /// sides 21 pt in, and the floating button 16 pt above it, its right edge on the key's.
    /// Frames as drawn, the key's offset down into the home indicator's area included.
    @Test("The floating button sits 16 pt above the key's right end")
    func floatingAboveKey() throws {
        let shown = try frames(isPresented: true)
        let key = try #require(shown.key, "the key was never laid out")
        #expect(874 - key.maxY == 21, "the ledge's bottom is off its place: \(key)")
        #expect(key.minX == 21 && 402 - key.maxX == 21, "the key's sides are off their place")
        #expect(key.minY - shown.floating.maxY == 16, "the gap is off: \(shown.floating)")
        #expect(shown.floating.maxX == key.maxX, "the right edges differ")
    }

    /// With no key in sight, as on an empty workout, the floating button sits low, its bottom
    /// where the key's ledge's bottom is and its right edge on the key's, so it never floats
    /// over a key that isn't there.
    @Test(
        "With no key, the floating button's bottom sits on the key's ledge line, at its right end",
    )
    func floatingLow() throws {
        let key = try #require(frames(isPresented: true).key, "the key was never laid out")
        let low = try frames(isPresented: false).floating
        #expect(low.maxY == key.maxY, "the low button's bottom is off the ledge line: \(low)")
        #expect(low.maxX == key.maxX, "the right edges differ")
    }

    /// The finish's "++" that pops off the key is only seen. Marked `accessibilityHidden`, the
    /// burst still stood in the tree as text over the key between bursts, at opacity 0, where
    /// automation and `axe describe-ui` read it. The key, a plain button, is the bar's only node.
    @Test("At rest, the key's finish burst puts nothing in the accessibility tree")
    func finishBurstLeavesNoNodeAtRest() throws {
        let leaves = try AccessibilityTree.leaves(
            of: Text(verbatim: "Bench press").frame(maxHeight: .infinity)
                .primaryKeyBar(isPresented: true, finishes: 3) { Button("Finish workout") { } },
        )
        let labels = leaves.map { $0.accessibilityLabel ?? "unlabeled at \($0.accessibilityFrame)" }
        #expect(labels == ["Bench press", "Finish workout"])
    }
}

#endif
