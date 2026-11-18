import SwiftUI

/// Exercises' icon in the drawer: a ticked circle, `checklist`'s, at the front of a stack of
/// three, each behind smaller and raised so only a crescent of it shows above the one in front. A
/// circle version of `rectangle.stack`, which SF Symbols has no circle of.
///
/// It stands in a label's icon as a symbol would beside `checklist`: the crescents' stroke is
/// `checklist`'s at the same size and weight, the whole stack stands as tall as `checklist`, and
/// it scales with Dynamic Type from the body text's point size, drawn in the foreground style.
/// Its frame is the whole stack's, so the stack centers on the name as `checklist` does. The
/// front circle is filled, with its check cut out in the stroke's width; the space around each
/// circle is cut out of those behind it. Both are cutouts, not paint, so they show whatever is
/// under the icon. That space is whole pixels from an edge on the pixel grid: a space a stroke
/// wide, smoothed across pixel edges, read as narrower and the crescents nearly merged.
public struct CircleStackSymbol: View {
    /// The point size of the text it sits beside, as a symbol's.
    @ScaledMetric(relativeTo: .body) private var pointSize: CGFloat = 17
    @Environment(\.displayScale) private var displayScale

    public init() { }

    public var body: some View {
        let shape = CircleStack(pointSize: pointSize, pixel: 1 / max(displayScale, 1))
        shape
            .frame(width: shape.frontSide, height: shape.height)
            .accessibilityHidden(true)
    }
}

/// The stack, filled: the front disc with its check cut out, and the crescents behind it, each
/// with its gap cut out.
private nonisolated struct CircleStack: Shape {
    let pointSize: CGFloat
    /// One device pixel, in points.
    let pixel: CGFloat

    /// One stroke: `checklist`'s, unrounded, so the two weigh the same.
    private var stroke: CGFloat {
        pointSize * strokePerPoint
    }

    /// The space between a circle and the crescent behind it: the stroke, up to whole pixels so
    /// it never closes.
    private var space: CGFloat {
        up(stroke)
    }

    /// The front circle's outer width, in whole pixels: what's left of `checklist`'s height
    /// once the two crescents above it, a space and a stroke each, are taken out.
    var frontSide: CGFloat {
        ((pointSize * heightPerPoint - 2 * (space + stroke)) / pixel).rounded() * pixel
    }

    /// The whole stack's height, from the front circle's bottom to the last crescent's top.
    var height: CGFloat {
        up(-outerTop(of: circles(bottom: 0)[backScales.count]))
    }

    func path(in rect: CGRect) -> Path {
        let circles = circles(bottom: rect.maxY, midX: rect.midX)
        let front = circles[0]
        var stack = disc(front.center, frontSide / 2).subtracting(checkmark(front.center))
        for (index, circle) in circles.enumerated().dropFirst() {
            var ring = disc(circle.center, circle.radius)
                .strokedPath(StrokeStyle(lineWidth: stroke))
            // Every circle in front clears its stroke and a space out of this one.
            for front in circles[..<index] {
                ring = ring.subtracting(disc(front.center, front.radius + stroke / 2 + space))
            }
            stack = stack.union(ring)
        }
        return stack
    }

    /// The circles, front first, each radius to its stroke's middle. Each circle behind has its
    /// inner edge a space above the outer edge of the one in front, moved up to the next pixel.
    private func circles(bottom: CGFloat, midX: CGFloat = 0) -> [Circle] {
        let radius = (frontSide - stroke) / 2
        var circles = [Circle(center: CGPoint(x: midX, y: bottom - frontSide / 2), radius: radius)]
        for scale in backScales {
            let innerTop = -up(space - outerTop(of: circles[circles.count - 1]))
            let backRadius = radius * scale
            let center = CGPoint(x: midX, y: innerTop - stroke / 2 + backRadius)
            circles.append(Circle(center: center, radius: backRadius))
        }
        return circles
    }

    /// The top of a circle's stroke's outer edge.
    private func outerTop(of circle: Circle) -> CGFloat {
        circle.center.y - circle.radius - stroke / 2
    }

    private func disc(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: 2 * radius,
            height: 2 * radius,
        ))
    }

    /// `checkmark.circle.fill`'s check, in the crescents' stroke.
    private func checkmark(_ center: CGPoint) -> Path {
        let radius = frontSide / 2
        var check = Path()
        check.addLines(checkPoints.map { CGPoint(
            x: center.x + $0.x * radius,
            y: center.y + $0.y * radius,
        ) })
        return check.strokedPath(StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
    }

    /// Up to whole pixels.
    private func up(_ length: CGFloat) -> CGFloat {
        (length / pixel - 0.001).rounded(.up) * pixel
    }

    private struct Circle {
        let center: CGPoint
        let radius: CGFloat
    }
}

/// `checklist`'s circle stroke per point of text at medium weight: 4.3 px at 3x beside 17 pt
/// text, measured on the simulator.
private nonisolated let strokePerPoint: CGFloat = 4.3 / 3 / 17

/// `checklist`'s height per point of text at medium weight: 51 px at 3x beside 17 pt text.
private nonisolated let heightPerPoint: CGFloat = 51.0 / 3 / 17

/// The two circles behind, as fractions of the front one.
private nonisolated let backScales: [CGFloat] = [0.86, 0.58]

/// The check's short end, corner, and long end, in the front circle's outer radii from its
/// center, y down: where `checkmark.circle.fill`'s sit, measured from its cutout.
private nonisolated let checkPoints: [CGPoint] = [
    CGPoint(x: -0.36, y: 0.04),
    CGPoint(x: -0.11, y: 0.34),
    CGPoint(x: 0.36, y: -0.30),
]

#Preview {
    VStack(alignment: .leading, spacing: Spacing.xs) {
        Button("Routines", systemImage: "checklist") { }
            .buttonStyle(.drawer(isSelected: false))
        Button { } label: {
            Label { Text(verbatim: "Exercises") } icon: { CircleStackSymbol() }
        }
        .buttonStyle(.drawer(isSelected: false))
    }
    .padding()
    .background(Color.pp(.background))
}
