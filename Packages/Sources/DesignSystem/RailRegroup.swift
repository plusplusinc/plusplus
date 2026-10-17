import SwiftUI

/// How a rail joins and parts its rows when a row's node is held and dragged to another row's:
/// the rule lives with the caller, and the rail asks it, so what it previews is what the drop
/// makes.
public struct RailRegroup<ID: Hashable> {
    /// What holding the first row's node and dropping it on the second's would make, or nil for
    /// nothing.
    public var preview: (ID, ID) -> RailGrouping<ID>?
    /// Makes it.
    public var commit: (ID, ID) -> Void

    public init(
        preview: @escaping (ID, ID) -> RailGrouping<ID>?,
        commit: @escaping (ID, ID) -> Void,
    ) {
        self.preview = preview
        self.commit = commit
    }
}

/// The groups a drop would leave: the rows joined to the next, and, for a join, the rows of the
/// group it makes, which draw in `railJoin` until the drop has settled.
public struct RailGrouping<ID: Hashable>: Equatable {
    public var links: Set<ID>
    public var joining: Set<ID>

    public init(links: Set<ID>, joining: Set<ID> = []) {
        self.links = links
        self.joining = joining
    }
}

/// A moment of a drag from a row's node: the row held, the row the finger is over, and what a
/// drop there would make.
struct RailRegroupState<ID: Hashable> {
    var held: ID
    var reach: ID
    /// The finger's y in the rail's space.
    var fingerY: CGFloat
    var grouping: RailGrouping<ID>?
}

/// The field behind the rows a drag is joining: `railJoin`, faint, edged in it, a little past the
/// rows on every side.
struct JoinField: View {
    /// Its rows' top and bottom in the rail's space.
    let span: ClosedRange<CGFloat>
    @ScaledMetric(relativeTo: .body) private var lineWidth = railLineWidth
    @ObserveHotReload private var hotReload

    private static let outset = Spacing.sm
    private static let overhang: CGFloat = 6
    private static let fill = 0.1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        shape
            .fill(.pp(.railJoin).opacity(Self.fill))
            .strokeBorder(.pp(.railJoin), lineWidth: lineWidth)
            .frame(height: span.upperBound - span.lowerBound + 2 * Self.overhang)
            .padding(.horizontal, -Self.outset)
            .offset(y: span.lowerBound - Self.overhang)
            .animation(RailDrag.gap, value: span)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .hotReloadable()
    }
}
