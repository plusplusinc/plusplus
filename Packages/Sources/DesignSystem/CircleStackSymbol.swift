import SwiftUI

/// Exercises' icon in the drawer: a circle with a checkmark in it, the front of a stack of three,
/// each behind smaller and raised so only a crescent of it shows above the one in front. A circle
/// version of `rectangle.stack`, which SF Symbols has no circle of.
///
/// It stands in a label's icon as a symbol would: sized and stroked from the body text's point
/// size, so it scales with Dynamic Type beside the drawer's symbols, and drawn in the foreground
/// style. Its frame is the front circle's, so it centers on the name as `checklist` does; the
/// crescents rise above it. The space around each circle is cut out of those behind it, not
/// painted over, so it shows whatever is under it.
public struct CircleStackSymbol: View {
    /// The point size of the text it sits beside, as a symbol's.
    @ScaledMetric(relativeTo: .body) private var pointSize: CGFloat = 17

    public init() { }

    public var body: some View {
        let shape = CircleStack(pointSize: pointSize)
        shape
            .frame(width: shape.frontSide, height: shape.frontSide)
            .accessibilityHidden(true)
    }
}

/// The stack's outline, filled: rings and a checkmark already stroked, each back ring with its
/// gap cut out.
private nonisolated struct CircleStack: Shape {
    let pointSize: CGFloat

    /// The front circle's radius, to its stroke's middle.
    private var radius: CGFloat {
        pointSize * radiusPerPoint
    }

    /// One stroke, and the space between a circle and the crescent behind it.
    private var stroke: CGFloat {
        pointSize * strokePerPoint
    }

    /// The front circle's outer width.
    var frontSide: CGFloat {
        2 * radius + stroke
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var circles: [(center: CGPoint, radius: CGFloat)] = [(center, radius)]
        // Each circle behind sits with its top one stroke and one space above the top of the one
        // in front.
        for scale in backScales {
            let front = circles[circles.count - 1]
            let top = front.center.y - front.radius - 2 * stroke
            let backRadius = radius * scale
            circles.append((CGPoint(x: center.x, y: top + backRadius), backRadius))
        }
        var outline = Path()
        for (index, circle) in circles.enumerated() {
            var ring = ring(circle.center, circle.radius)
            // Every circle in front clears its stroke and a space out of this one.
            for front in circles[..<index] {
                ring = ring.subtracting(disc(front.center, front.radius + stroke / 2 + stroke))
            }
            outline = outline.union(ring)
        }
        return outline.union(checkmark(center))
    }

    private func ring(_ center: CGPoint, _ radius: CGFloat) -> Path {
        disc(center, radius).strokedPath(StrokeStyle(lineWidth: stroke))
    }

    private func disc(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: 2 * radius,
            height: 2 * radius,
        ))
    }

    /// A check as `checkmark.circle`'s sits in its circle, in the circles' stroke.
    private func checkmark(_ center: CGPoint) -> Path {
        var check = Path()
        check.addLines(checkPoints.map { CGPoint(
            x: center.x + $0.x * radius,
            y: center.y + $0.y * radius,
        ) })
        return check.strokedPath(StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
    }
}

/// The front circle's radius per point of text: 10.5 pt beside 34 pt text in the chosen design.
private nonisolated let radiusPerPoint: CGFloat = 10.5 / 34

/// The stroke per point of text: the design's 2.2 pt at 34 pt was drawn beside regular-weight
/// symbols; the drawer's are medium, whose strokes SF Symbols draws 1.2 times as wide.
private nonisolated let strokePerPoint: CGFloat = 2.2 / 34 * 1.2

/// The two circles behind, as fractions of the front one.
private nonisolated let backScales: [CGFloat] = [0.86, 0.58]

/// The checkmark's short end, corner, and long end, in front radii from its center, y down.
private nonisolated let checkPoints: [CGPoint] = [
    CGPoint(x: -0.42, y: -0.02),
    CGPoint(x: -0.10, y: 0.32),
    CGPoint(x: 0.45, y: -0.36),
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
