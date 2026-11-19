import SwiftUI

/// The rest between two sets of one exercise, on the rail beside it: the rail widened over the
/// rest's span into the bar a rest between exercises fills (`RestBar`), its gray, its width, its
/// round ends, from the word "Rest" down to the next set's line under it (`SetRestSpan`), so the
/// fill reads as running toward that set. It widens out of the rail as the rest swaps into the
/// numbers' place, and the fill, the rest's blue, runs down it at one speed from `starts` to the
/// rest's end, a line the bar's width. At the end, as the next set's numbers grow back up, the
/// fill and the bar narrow away together into the plain rail. The exercise's node stays lit,
/// steady green, through it all. `ends` animates: after a + or −, the fill glides to its new
/// place on the tap's animation; `grown` and `gone` run on the swaps' animations.
struct SetRestBar: View, Animatable {
    typealias Stage = SetRestStage

    let starts: Date
    let heldAt: Date?
    /// The bar's top and bottom, in the rail's space, at the node's x.
    let top: CGPoint
    let bottom: CGFloat
    var ends: Double
    var grown: Double
    var gone: Double
    @ScaledMetric(relativeTo: .body) private var width = RestBar.size
    @ScaledMetric(relativeTo: .body) private var railWidth = railLineWidth

    init(starts: Date, ends: Date, heldAt: Date?, stage: Stage, top: CGPoint, bottom: CGFloat) {
        self.starts = starts
        self.heldAt = heldAt
        self.top = top
        self.bottom = bottom
        self.ends = ends.timeIntervalSinceReferenceDate
        grown = stage == .coming ? 0 : 1
        gone = stage == .going ? 1 : 0
    }

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(ends, AnimatablePair(grown, gone)) }
        set { (ends, grown, gone) = (newValue.first, newValue.second.first, newValue.second.second)
        }
    }

    var body: some View {
        let schedule = AnimationTimelineSchedule(minimumInterval: 1.0 / 60, paused: heldAt != nil)
        TimelineView(schedule) { context in
            let now = (heldAt ?? context.date).timeIntervalSinceReferenceDate
            let span = ends - starts.timeIntervalSinceReferenceDate
            let filled = span > 0
                ? min(max((now - starts.timeIntervalSinceReferenceDate) / span, 0), 1) : 1
            let length = max(bottom - top.y, 0)
            let bar = railWidth + (width - railWidth) * CGFloat(grown * (1 - gone))
            ZStack(alignment: .top) {
                Capsule().fill(.pp(.rail))
                    .frame(width: bar, height: length + bar)
                Capsule().fill(.pp(.restFill))
                    // The bar's width as it fills, narrowing to none as the rest goes.
                    .frame(
                        width: width * CGFloat(min(grown, 1 - gone)),
                        height: (length + width) * CGFloat(filled),
                    )
            }
            .frame(height: length + bar, alignment: .top)
            .position(x: top.x, y: top.y + length / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension Rail {
    /// The bar of a rest between two sets of `travel.from`, at its node's x over the rest's span.
    @ViewBuilder
    func setRestBar(
        _ travel: RailTravel<RowID>,
        _ stage: SetRestStage,
        _ nodes: [AnyHashable: Anchor<CGPoint>],
        in proxy: GeometryProxy,
    ) -> some View {
        if let node = nodes[AnyHashable(travel.from)].map({ proxy[$0] }),
           let span = setRestSpan.map({ proxy[$0] })
        {
            SetRestBar(
                starts: travel.starts,
                ends: travel.ends,
                heldAt: travel.heldAt,
                stage: stage,
                top: CGPoint(x: node.x, y: span.minY),
                bottom: span.maxY,
            )
            .transition(.identity)
        }
    }
}

/// Where a rest between two sets' bar is in its change, as the rest and the next set swap places
/// (`SetRestBar`).
public enum SetRestStage: Sendable {
    /// The set is logged, the rest not yet up: the plain rail.
    case coming
    /// The rest is up, or swapping in: the bar, filling.
    case shown
    /// The rest is over, the next set swapping back: narrowing into the rail.
    case going
}

/// The span of a rest between two sets beside the exercise's numbers' room: from the top of the
/// word "Rest" to the middle of the next set's line. Kept by the rail, which reads it with its
/// rows' nodes.
struct SetRestSpan: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
