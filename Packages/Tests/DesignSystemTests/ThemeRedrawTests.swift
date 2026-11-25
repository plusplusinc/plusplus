// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// A theme picked recolors what is already on screen: `Color.pp` resolves from the theme around
/// it each time it draws, so a view two levels under the one that holds the theme redraws in
/// the new one, with nothing of its own changed. A snapshot draws one moment and cannot show a
/// change, so this hosts the view and reads what it drew before and after.
@Suite("Theme redraw")
struct ThemeRedrawTests {
    @Observable
    final class Picked {
        var theme = Theme.plusPlus
    }

    private struct Root: View {
        let picked: Picked

        var body: some View {
            Middle()
                .environment(\.theme, picked.theme)
                .environment(\.colorScheme, .dark)
        }
    }

    private struct Middle: View {
        var body: some View {
            VStack { Leaf() }
        }
    }

    private struct Leaf: View {
        var body: some View {
            Rectangle()
                .fill(.pp(.accent))
                .ignoresSafeArea()
        }
    }

    @Test("A view two levels under a changed theme redraws in the new theme's active color")
    func leafRedraws() throws {
        let picked = Picked()
        let host = UIHostingController(rootView: Root(picked: picked))
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.settle()
        let before = try Self.center(of: host)
        picked.theme = .ocean
        window.settle()
        let after = try Self.center(of: host)
        #expect(Self.near(before, Self.dark(.plusPlus)), "Before: \(before)")
        #expect(Self.near(after, Self.dark(.ocean)), "After the change: \(after)")
    }

    /// The theme's dark `accent`, as 8-bit sRGB.
    private static func dark(_ theme: Theme) -> [Int] {
        var environment = EnvironmentValues()
        environment.theme = theme
        environment.colorScheme = .dark
        let color = theme.resolve(.accent, in: environment)
        return [color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) }
    }

    /// Within two 8-bit steps a channel, for the renderer's rounding.
    private static func near(_ drawn: [Int], _ expected: [Int]) -> Bool {
        zip(drawn, expected).allSatisfy { abs($0 - $1) <= 2 }
    }

    /// The window's middle pixel, as 8-bit sRGB, rendered from its layers: the window has no
    /// scene, so `drawHierarchy` has nothing to copy.
    private static func center(of host: UIViewController) throws -> [Int] {
        let bounds = host.view.bounds
        let point = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: point, format: format).image {
            host.view.layer.render(in: $0.cgContext)
        }
        let cgImage = try #require(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel.prefix(3).map(Int.init)
    }
}

#endif
