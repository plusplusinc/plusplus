import SwiftUI

/// The rest's stretch of the rail as a bar the green fills: the rail itself, in its gray, widened
/// over `SetMotion.restSpan` to `width` with round ends, `grown` of the way from the rail's own
/// width. It widens as the rest opens (`RailTravelDot`) and narrows back as the green leaves it
/// for the next node (`RailPulseRun`).
nonisolated struct RestBar: Shape {
    let route: RailRoute
    let width: CGFloat
    /// The rail's own width, which it widens from and narrows back to.
    let railWidth: CGFloat
    /// The dot's size, whose top edge the bar's top meets as the dot comes into it.
    let dotSize: CGFloat
    var grown: Double

    /// The bar's width at its full, about the green line's in a move with no rest.
    static let size: CGFloat = 6

    /// Where the move's pulse takes the green on from after a rest, along `route` from 0 to 1:
    /// the fill's top end, a dot `size` wide come into a bar `barWidth` wide, once it fills; the
    /// leading end itself before, `from`.
    static func tail(
        of rest: RestHandoff,
        from: Double,
        on route: RailRoute,
        size: CGFloat,
        barWidth: CGFloat,
    ) -> Double {
        guard rest.tail < from, route.length > 0 else { return from }
        let top = PulseShape.fillTail(
            top: route.length * rest.tail,
            width: barWidth,
            size: size,
        )
        return min(max(Double(top / route.length), 0), from)
    }

    var animatableData: Double {
        get { grown }
        set { grown = newValue }
    }

    func path(in _: CGRect) -> Path {
        let span = SetMotion.restSpan
        let points = route.stretch(
            from: PulseShape.fillTail(
                top: route.length * span.lowerBound,
                width: width,
                size: dotSize,
            ),
            to: route.length * span.upperBound,
        )
        guard grown > 0, route.length > 0, let first = points.first else { return Path() }
        var line = Path()
        line.move(to: first)
        for point in points.dropFirst() {
            line.addLine(to: point)
        }
        let eased = 1 - pow(1 - grown, 3)
        let drawn = railWidth + (width - railWidth) * CGFloat(eased)
        return line.strokedPath(StrokeStyle(lineWidth: drawn, lineCap: .round))
    }
}

/// The rest's bar in the rail's gray, at the scaled sizes.
struct RestBarView: View {
    let route: RailRoute
    let grown: Double
    @ScaledMetric(relativeTo: .body) private var width = RestBar.size
    @ScaledMetric(relativeTo: .body) private var railWidth = railLineWidth
    @ScaledMetric(relativeTo: .body) private var dotSize = currentNodeSize

    var body: some View {
        RestBar(route: route, width: width, railWidth: railWidth, dotSize: dotSize, grown: grown)
            .fill(.pp(.rail))
    }
}

nonisolated extension PulseShape {
    /// A capsule's width with the area of a circle at `size`, its two ends' centers `apart`.
    static func width(apart: CGFloat, size: CGFloat) -> CGFloat {
        let round = CGFloat.pi / 2
        return ((apart * apart + round * round * size * size).squareRoot() - apart) / round
    }

    /// The rest's green from the bar's top to its leading end, the end's center `along` the route,
    /// the top's `top`: a capsule of the dot's area while short, never thinner than the bar.
    static func fill(
        route: RailRoute,
        top: CGFloat,
        along: CGFloat,
        size: CGFloat,
        barWidth: CGFloat,
    ) -> Path {
        // The top edge stays where the dot's was as it came in, so as the line thins its top
        // holds still: its end's center rises by half what its width gives up.
        var width = size
        for _ in 0 ..< 3 {
            let tail = Self.fillTail(top: top, width: width, size: size)
            width = max(Self.width(apart: max(along - tail, 0), size: size), barWidth)
        }
        var line = Path()
        let points = route.stretch(
            from: Self.fillTail(top: top, width: width, size: size),
            to: along,
        )
        if let first = points.first {
            line.move(to: first)
            for point in points.dropFirst() {
                line.addLine(to: point)
            }
        }
        return line.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round))
            .union(Circle(center: route.point(at: along), radius: width / 2).path)
    }

    /// The center of the fill's top end, `width` wide, its top edge the dot's at `top`.
    static func fillTail(top: CGFloat, width: CGFloat, size: CGFloat) -> CGFloat {
        top - (size - width) / 2
    }
}
