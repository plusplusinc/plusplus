// Runs only where UIKit exists, as the suites that use it do.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import UIKit

/// Where a view draws, pixel by pixel: `root` hosted on a clear background in a phone-sized
/// window at `category`, rendered at 3 pixels a point.
@MainActor
struct Coverage {
    static let scale = 3
    let width: Int
    let height: Int
    private let alpha: [UInt8]

    init(of root: some View, at category: UIContentSizeCategory) throws {
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        let window = UIWindow.sceneless(hosting: host, at: category)
        defer { window.isHidden = true }
        window.settle()
        let format = UIGraphicsImageRendererFormat()
        format.scale = CGFloat(Self.scale)
        format.opaque = false
        // The window has no scene, so it is never on a screen for `drawHierarchy` to copy; its
        // layers render all the same.
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image {
            host.view.layer.render(in: $0.cgContext)
        }
        guard let cgImage = image.cgImage else { throw Unrendered() }
        (width, height) = (cgImage.width, cgImage.height)
        // Drawn into an alpha-only context, a byte a pixel: picking every fourth byte out of
        // RGBA took most of a second an image in a Debug build.
        var alpha = [UInt8](repeating: 0, count: width * height)
        alpha.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: cgImage.width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue,
            )
            context?.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height),
            )
        }
        self.alpha = alpha
    }

    /// Whether the pixel at `x` across and `y` down is more than half covered.
    func covered(_ x: Int, _ y: Int) -> Bool {
        alpha[y * width + x] > 128
    }

    /// Whether any pixel of column `x` is more than half covered, in `rows` if given.
    func covered(column x: Int, rows: Range<Int>? = nil) -> Bool {
        (rows ?? 0 ..< height).contains { covered(x, $0) }
    }

    /// Whether any pixel of row `y` is more than half covered, in `columns` if given.
    func covered(row y: Int, columns: Range<Int>? = nil) -> Bool {
        (columns ?? 0 ..< width).contains { covered($0, y) }
    }

    private struct Unrendered: Error { }
}

#endif
