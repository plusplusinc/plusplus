// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// Where a ruler rests when the text size changes while it is on screen, as the system changes
/// it: its spacing scales with the labels, so every tick moves, and the value has to stay under
/// the line. A snapshot draws each size fresh, so it cannot see an offset kept from the size
/// before.
@MainActor
@Suite("Value ruler after a text size change")
struct ValueRulerTextSizeTests {
    private static let width: CGFloat = 370
    private static let spacing: CGFloat = 10
    private static let range = 5.0 ... 6000.0
    private static let value = 60.0

    @Test("A ruler keeps its value under its line through every text size, up and down")
    func keepsItsValueAsTheTextSizeChanges() throws {
        let host = UIHostingController(rootView: ValueRuler(
            value: Self.value,
            range: Self.range,
            tick: 5,
            medium: 15,
            major: 30,
            spacing: Self.spacing,
            onChange: { _ in },
        )
        .frame(width: Self.width))
        host.safeAreaRegions = []
        let window = UIWindow.sceneless(hosting: host, at: .large)
        window.settle()
        let sizes: [UIContentSizeCategory] = [
            .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge,
            .extraExtraExtraLarge, .accessibilityMedium, .accessibilityLarge,
            .accessibilityExtraLarge, .accessibilityExtraExtraLarge,
            .accessibilityExtraExtraExtraLarge, .large,
        ]
        var placed: [String] = []
        for size in sizes {
            window.traitOverrides.preferredContentSizeCategory = size
            window.settle()
            let scroll = try #require(window.firstScrollView, "The ruler has no scroll view")
            let spacing = UIFontMetrics(forTextStyle: .subheadline)
                .scaledValue(for: Self.spacing, compatibleWith: window.traitCollection)
            let scale = RulerScale(range: Self.range, tick: 5, spacing: spacing)
            let value = scale.value(at: scroll.contentOffset.x)
            placed.append("\(size.rawValue): \(value.formatted())")
        }
        let off = placed.filter { !$0.hasSuffix(": \(Self.value.formatted())") }
        #expect(off.isEmpty, "The line left \(Self.value.formatted()) at \(off)")
    }
}

#endif

