import SwiftUI

/// A row's label with its rest under it (`RestBlock`), stacked as the rail stacks its rows, so
/// the rest moves with the label's height on every frame. The label stands at least as tall as a
/// resting row's floor (`restingLabelFloor`), the height a shrinking label stands at until its
/// shrink ends: shorter at rest, a one-line detail's label let the rest under it jump up 8 pt as
/// the shrink ended. `onRestHeight` hears the rest's height as it lays out: all the row gives back
/// as the rest closes. Before a superset's next round its rest opens above its first member's
/// label instead (`restAbove`), the row's node staying on the label's first line, so the rest
/// sits on the rail's line into the node, between the row above and the label, with the room
/// under its count a rest between exercises has before the next name (`restIsAboveLabel`).
public struct LabelWithRest<Label: View>: View {
    let label: Label
    let rest: RestBlock
    let restAbove: RestBlock
    let onRestHeight: (CGFloat) -> Void
    @Environment(\.restingLabelFloor) private var floor

    public init(
        label: Label,
        rest: RestBlock,
        restAbove: RestBlock = RestBlock(stage: .none, length: 0),
        onRestHeight: @escaping (CGFloat) -> Void = { _ in },
    ) {
        self.label = label
        self.rest = rest
        self.restAbove = restAbove
        self.onRestHeight = onRestHeight
    }

    public var body: some View {
        RestsAroundLabel {
            restAbove.environment(\.restIsAboveLabel, true)
            label.frame(minHeight: floor, alignment: .top)
            rest
                .onGeometryChange(for: CGFloat.self, of: \.size.height, action: onRestHeight)
        }
    }
}

extension EnvironmentValues {
    /// Whether a rest opens above its row's label, before a superset's next round.
    @Entry var restIsAboveLabel = false
}

/// A rest above, a label, and a rest below, stacked as `RailStack` stacks them, its text
/// baselines the label's: the rest above, laid out even while closed, would otherwise lend the
/// row its "Rest", and the row's node would sit on it.
private struct RestsAroundLabel: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = sizes(subviews, width: proposal.width)
        return CGSize(
            width: sizes.map(\.width).max() ?? 0,
            height: sizes.map(\.height).reduce(0, +),
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let offer = ProposedViewSize(width: bounds.width, height: nil)
        var top = bounds.minY
        for (subview, size) in zip(subviews, sizes(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX, y: top), proposal: offer)
            top += size.height
        }
    }

    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) -> CGFloat? {
        guard subviews.count == 3,
              guide == .firstTextBaseline || guide == .railNodeBaseline
        else { return nil }
        let offer = ProposedViewSize(width: bounds.width, height: nil)
        return subviews[0].sizeThatFits(offer).height + subviews[1].dimensions(in: offer)[guide]
    }

    private func sizes(_ subviews: Subviews, width: CGFloat?) -> [CGSize] {
        let offer = ProposedViewSize(width: width, height: nil)
        return subviews.map { $0.sizeThatFits(offer) }
    }
}
