// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// Void chosen recolors what is already on screen: `Color.pp` resolves from the
/// environment each time it draws, so a view two levels under the one that holds the choice
/// redraws in the new colors, with nothing of its own changed. A snapshot draws one moment and
/// cannot show a change, so this hosts the view and reads what it drew before and after.
@Suite("Void redraw")
struct VoidRedrawTests {
    @Observable
    final class Chosen {
        var isVoid = false
    }

    private struct Root: View {
        let chosen: Chosen

        var body: some View {
            Middle()
                .environment(\.isVoid, chosen.isVoid)
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
                .fill(.pp(.background))
                .ignoresSafeArea()
        }
    }

    @Test("A view two levels under the choice redraws from PlusPlus dark's ground to black")
    func leafRedraws() throws {
        let chosen = Chosen()
        let host = UIHostingController(rootView: Root(chosen: chosen))
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.settle()
        let before = try Self.center(of: host)
        chosen.isVoid = true
        window.settle()
        let after = try Self.center(of: host)
        #expect(Self.near(before, Self.background(isVoid: false)), "Before: \(before)")
        #expect(Self.near(after, [0, 0, 0]), "After the change: \(after)")
    }

    /// The screen the open drawer slides aside: a plain ground, at the drawer's end.
    private struct OpenDrawer: View {
        let isVoid: Bool
        let scheme: ColorScheme

        var body: some View {
            SideDrawer(isOpen: .constant(true), progress: 1) {
                Color.clear
            } content: {
                Color.pp(.background).ignoresSafeArea()
            }
            .environment(\.isVoid, isVoid)
            .environment(\.colorScheme, scheme)
        }
    }

    /// The sliver of screen beside the open drawer, as 8-bit sRGB.
    private static func sliver(isVoid: Bool, scheme: ColorScheme) throws -> [Int] {
        let host = UIHostingController(rootView: OpenDrawer(isVoid: isVoid, scheme: scheme))
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.settle()
        return try center(of: host, x: host.view.bounds.maxX - DrawerMetrics.sliver / 2)
    }

    /// In the screen's black the dimmed sliver was as black as the drawer; Void lifts its ground
    /// to `Palette.voidUnderDrawer`. Light and Dark draw only the dim, as before: Void changes
    /// nothing where the app is light.
    @Test("Under an open drawer Void's screen lifts off black, and Light and Dark only dim")
    func drawerLift() throws {
        let lift = Palette.voidUnderDrawer
        let lifted = [lift.red, lift.green, lift.blue].map { Int(($0 * 255).rounded()) }
        let void = try Self.sliver(isVoid: true, scheme: .dark)
        #expect(Self.near(void, lifted), "Void: \(void)")
        let dark = try Self.sliver(isVoid: false, scheme: .dark)
        #expect(Self.near(dark, Self.dimmed(Self.background(isVoid: false))), "Dark: \(dark)")
        let light = try Self.sliver(isVoid: false, scheme: .light)
        #expect(try Self.sliver(isVoid: true, scheme: .light) == light, "Light: \(light)")
    }

    /// `ground` under PlusPlus dark's `dim`, as the drawer lays it over the screen.
    private static func dimmed(_ ground: [Int]) -> [Int] {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        let dim = Color.pp(.dim).resolve(in: environment)
        let over = [dim.red, dim.green, dim.blue].map { Double($0) * 255 }
        let alpha = Double(dim.opacity)
        return zip(ground, over).map { Int((Double($0) * (1 - alpha) + $1 * alpha).rounded()) }
    }

    /// The dark `background`, as 8-bit sRGB.
    private static func background(isVoid: Bool) -> [Int] {
        var environment = EnvironmentValues()
        environment.isVoid = isVoid
        environment.colorScheme = .dark
        let color = Color.pp(.background).resolve(in: environment)
        return [color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) }
    }

    /// Within two 8-bit steps a channel, for the renderer's rounding.
    private static func near(_ drawn: [Int], _ expected: [Int]) -> Bool {
        zip(drawn, expected).allSatisfy { abs($0 - $1) <= 2 }
    }

    /// The window's pixel at `x` (its middle by default) halfway down, as 8-bit sRGB, rendered
    /// from its layers: the window has no scene, so `drawHierarchy` has nothing to copy.
    private static func center(of host: UIViewController, x: CGFloat? = nil) throws -> [Int] {
        let bounds = host.view.bounds
        let point = CGRect(x: x ?? bounds.midX, y: bounds.midY, width: 1, height: 1)
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
