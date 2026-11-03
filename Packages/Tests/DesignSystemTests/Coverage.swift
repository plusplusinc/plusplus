// Runs only where UIKit exists, as the suites that use it do.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import UIKit

/// Where a view draws, pixel by pixel: `root` hosted on a clear background in a phone-sized
/// window at `category`, rendered at 3 pixels a point, only as far as its own size and a
/// margin, where the window centers it.
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
        let bounds = host.view.bounds
        let size = host.sizeThatFits(in: bounds.size)
        let drawn = CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height,
        )
        // A margin for what draws past the view's frame, as a letter's overhang can.
        .insetBy(dx: -8, dy: -8).integral
        let image = UIGraphicsImageRenderer(bounds: drawn, format: format).image {
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

    /// The columns, left to right, with a pixel more than half covered in `rows`.
    func coveredColumns(in rows: Range<Int>? = nil) -> [Int] {
        let rows = rows ?? 0 ..< height
        return (0 ..< width).filter { x in rows.contains { alpha[$0 * width + x] > 128 } }
    }

    /// The rows, top to bottom, with a pixel more than half covered in `columns`.
    func coveredRows(in columns: Range<Int>? = nil) -> [Int] {
        let columns = columns ?? 0 ..< width
        return (0 ..< height).filter { y in columns.contains { alpha[y * width + $0] > 128 } }
    }

    /// `indices`, ascending, as runs of consecutive ones.
    static func runs(_ indices: [Int]) -> [ClosedRange<Int>] {
        indices.reduce(into: []) { runs, index in
            if let last = runs.last, last.upperBound == index - 1 {
                runs[runs.count - 1] = last.lowerBound ... index
            } else {
                runs.append(index ... index)
            }
        }
    }

    private struct Unrendered: Error { }
}

#endif
