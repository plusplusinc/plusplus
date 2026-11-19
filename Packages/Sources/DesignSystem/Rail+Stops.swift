import SwiftUI

// Where a pulse sets off and lands: the rows' nodes, and a rest open under a row, where the dot
// waits for the rest's length.

extension Rail {
    /// The way from `fromStop` to `toStop` for a pulse: up a superset's loop to its first member,
    /// from a later one in the same superset; straight along the rail otherwise, to or from a
    /// rest included.
    func route(
        _ fromStop: RailStop<RowID>,
        _ toStop: RailStop<RowID>,
        _ nodes: [AnyHashable: Anchor<CGPoint>],
        in proxy: GeometryProxy,
    ) -> RailRoute? {
        guard let from = point(of: fromStop, nodes, in: proxy),
              let to = point(of: toStop, nodes, in: proxy)
        else { return nil }
        let ids = data.map(\.id)
        guard fromStop.isNode, toStop.isNode,
              let start = ids.firstIndex(of: toStop.row),
              let end = ids.firstIndex(of: fromStop.row),
              start < end, ids[start ..< end].allSatisfy(links.contains)
        else { return .line(from: from, to: to) }
        return .loop(from: from, to: to, x: pen.runX(nodeX: from.x), radius: pen.radius)
    }

    /// Where `stop` is on each frame: a row's node; or, for a rest, on the rail's line under the
    /// row's node, as high as the rest reports it (`View.restStop(_:)`).
    func point(
        of stop: RailStop<RowID>,
        _ nodes: [AnyHashable: Anchor<CGPoint>],
        in proxy: GeometryProxy,
    ) -> CGPoint? {
        guard let node = nodes[AnyHashable(stop.row)].map({ proxy[$0] }) else { return nil }
        guard case let .rest(row) = stop else { return node }
        return nodes[AnyHashable(RestStopKey(row: AnyHashable(row)))].map { CGPoint(
            x: node.x,
            y: proxy[$0].y,
        ) }
    }
}

/// A row's rest stop among the rows' nodes (`RowNodes`), apart from its node.
struct RestStopKey: Hashable {
    let row: AnyHashable
}

/// The rest stops in a view: a rest open, or opening or closing, under a row's label.
struct RestStops: PreferenceKey {
    static let defaultValue: [Anchor<CGPoint>] = []

    static func reduce(value: inout [Anchor<CGPoint>], nextValue: () -> [Anchor<CGPoint>]) {
        value += nextValue()
    }
}

extension View {
    /// Reports this view's center as its row's rest stop while `isShown`: as high as the dot
    /// waits there.
    func restStop(_ isShown: Bool) -> some View {
        anchorPreference(key: RestStops.self, value: .center) { isShown ? [$0] : [] }
    }

    /// Reports a rail row's rest stop by the row's id, among the nodes (`RowNodes`).
    func reportingRestStop(of id: some Hashable) -> some View {
        backgroundPreferenceValue(RestStops.self) { stops in
            Color.clear.preference(
                key: RowNodes.self,
                value: stops.first.map { [AnyHashable(RestStopKey(row: AnyHashable(id))): $0] }
                    ?? [:],
            )
        }
    }
}

/// The workout's dot waiting at a rest: the current node's size and steady green, alone on the
/// rail's line.
struct RestDot: View {
    let center: CGPoint
    @ScaledMetric(relativeTo: .body) private var size = currentNodeSize

    var body: some View {
        Circle()
            .fill(.pp(.accent))
            .frame(width: size, height: size)
            .position(center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
