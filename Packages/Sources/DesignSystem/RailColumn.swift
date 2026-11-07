import SwiftUI

/// The rail column's width at the default text size, centered on the rail's line.
private nonisolated let railColumnWidth: CGFloat = 44

/// Room before the rail column, so its line runs down from the center of ++ and under the
/// primary key's round end, which covers a node beside it where a line 4 pt further out let a
/// sliver of the node show. It is the toolbar's 20 pt margin before ++ less the screen's 16 pt
/// one, so at the default text size the line runs under ++'s center; at larger sizes the column
/// grows with its icon and the line moves right of it. Only before it: what follows keeps its
/// distance from the line.
nonisolated let railColumnLead: CGFloat = 4

/// How far a node's center is from the rail column's leading edge, at the default text size.
nonisolated let railNodeCenter = railColumnLead + railColumnWidth / 2

/// The rail column as a row's node holds it: the key's icon, held invisibly, gives it the key's
/// width and baseline at every text size, and `node` is drawn centered on it, before the room
/// before the column.
struct RailNodeColumn<Node: View>: View {
    @ViewBuilder var node: Node

    var body: some View {
        RailNodeGlyph()
            .railColumnCenter()
            .overlay { node }
            .padding(.leading, railColumnLead)
    }
}

extension RailNodeColumn where Node == EmptyView {
    /// The column alone, as the rail measures it.
    init() {
        node = EmptyView()
    }
}

/// The key's icon, held invisibly: what a node centers on, on a row's first line.
struct RailNodeGlyph: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.ppButton)
            .hidden()
    }
}

extension View {
    /// The rail column: the leading strip where rows put their nodes and a key its icon. At
    /// large text sizes it grows with what it holds, keeping an inset, rather than clipping it.
    func railColumn() -> some View {
        railColumnCenter().padding(.leading, railColumnLead)
    }

    /// The rail column without the room before it: what a node centers on.
    fileprivate func railColumnCenter() -> some View {
        padding(.horizontal, Spacing.sm).frame(minWidth: railColumnWidth)
    }
}
