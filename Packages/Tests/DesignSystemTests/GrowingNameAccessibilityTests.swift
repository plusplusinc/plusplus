// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// What a growing name puts in the accessibility tree, as automation and `axe describe-ui` read
/// it: its text, and nothing for the node's glyph it measures. Marked `accessibilityHidden` on top
/// of the `hidden()` that already kept it out, the glyph came back as an unlabeled 18 × 17 pt
/// element at the start of every row's name: the modifier gave the empty view a node of its own.
@MainActor
@Suite("Growing name's accessibility")
struct GrowingNameAccessibilityTests {
    @Test("A name, at rest, growing, or grown, puts only its text in the tree", arguments: [
        CGFloat(0), 0.5, 1,
    ])
    func onlyText(growth: CGFloat) throws {
        let leaves = try AccessibilityTree.leaves(of: GrowingName(
            title: "Deadlift",
            growth: growth,
        ))
        #expect(!leaves.isEmpty, "Nothing in the tree")
        for leaf in leaves {
            #expect(
                leaf.accessibilityLabel == "Deadlift",
                "\(leaf.accessibilityLabel ?? "unlabeled") at \(leaf.accessibilityFrame)",
            )
        }
    }
}

/// The accessibility tree SwiftUI builds for a hosted view, as automation reads it. SwiftUI builds
/// it only once accessibility is on, which nothing public turns on in a test process, so this
/// turns it on as the system does for VoiceOver and automation, through libAccessibility, and
/// reads each node's `automationElements`, the children `axe describe-ui` and XCTest see.
@MainActor
enum AccessibilityTree {
    /// The nodes with no children under `root`.
    static func leaves(of root: some View) throws -> [NSObject] {
        try setAccessibilityEnabled(true)
        defer { try? setAccessibilityEnabled(false) }
        let host = UIHostingController(rootView: root)
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.settle()
        return leaves(under: host.view)
    }

    /// Every node under `root`, each before its children.
    static func nodes(of root: some View) throws -> [NSObject] {
        try setAccessibilityEnabled(true)
        defer { try? setAccessibilityEnabled(false) }
        let host = UIHostingController(rootView: root)
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.settle()
        return nodes(under: host.view)
    }

    private static func nodes(under node: NSObject) -> [NSObject] {
        [node] + automationElements(of: node).flatMap { nodes(under: $0) }
    }

    private static func leaves(under node: NSObject) -> [NSObject] {
        let children = automationElements(of: node)
        return children.isEmpty ? [node] : children.flatMap { leaves(under: $0) }
    }

    private static func automationElements(of node: NSObject) -> [NSObject] {
        let selector = NSSelectorFromString("automationElements")
        guard node.responds(to: selector) else { return [] }
        return node.perform(selector)?.takeUnretainedValue() as? [NSObject] ?? []
    }

    private static func setAccessibilityEnabled(_ enabled: Bool) throws {
        typealias SetEnabled = @convention(c) (Bool) -> Void
        let symbol = try #require(
            dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW)
                .flatMap { dlsym($0, "_AXSApplicationAccessibilitySetEnabled") },
            "libAccessibility has no switch to turn accessibility on",
        )
        unsafeBitCast(symbol, to: SetEnabled.self)(enabled)
    }
}

#endif
