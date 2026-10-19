import SwiftUI

/// How a rail groups its rows when a row's node is held and dragged to another row's: the rule
/// lives with the caller, and the rail asks it, so what it previews is what the drop
/// makes.
public struct RailRegroup<ID: Hashable> {
    /// What holding the first row's node and dropping it on the second's would make, or nil for
    /// nothing.
    public var preview: (ID, ID) -> RailGrouping<ID>?
    /// The rows a press on a row's node picks up, before the finger moves, which sit in the raised
    /// field until it does.
    public var pickUp: (ID) -> Set<ID>
    /// Makes it.
    public var commit: (ID, ID) -> Void

    public init(
        preview: @escaping (ID, ID) -> RailGrouping<ID>?,
        pickUp: @escaping (ID) -> Set<ID>,
        commit: @escaping (ID, ID) -> Void,
    ) {
        self.preview = preview
        self.pickUp = pickUp
        self.commit = commit
    }
}

/// The groups a drop would leave: the rows joined to the next; the rows the drag spans, which sit
/// in one well while it is held; and the rows of the group it makes, the span's or none,
/// whose loop flashes in `railJoin` as it drops.
public struct RailGrouping<ID: Hashable>: Equatable {
    public var links: Set<ID>
    public var span: Set<ID>

    public init(links: Set<ID>, span: Set<ID>) {
        self.links = links
        self.span = span
    }

    /// The rows of the group a drop makes: the span's, or none when it is one row.
    public var superset: Set<ID> {
        span.count > 1 ? span : []
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
    /// The rows the press picked up, in the field until the finger reaches another row.
    var pickedUp: Set<ID> = []
    /// The finger is over a bar, or past the screen's edge, where letting go changes nothing.
    var isOverBar = false

    /// What the rail draws: the preview, or, over a bar, the rows as they are, since a drop there
    /// makes nothing.
    var shown: RailGrouping<ID>? {
        isOverBar ? nil : grouping
    }

    /// The rows in the well: the span, or, over the held row, what the press picked up.
    var field: Set<ID> {
        grouping?.span ?? (reach == held ? pickedUp : [])
    }
}
