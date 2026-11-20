import SwiftUI

extension View {
    /// Reports, while `isOn`, the pitch `resting` would give the rail as a row at rest: its
    /// height laid out as `railRow()` lays out a row, top to the next row's top, since the rail
    /// stacks its rows with no spacing. For a row on screen grown, as the current exercise is:
    /// a move off it lands by what it gives back as it shrinks. Measured from a hidden copy, at
    /// this view's width, that draws nothing and marks no node; built only while on.
    public func reportingRailPitch<Resting: View>(
        isOn: Bool,
        of resting: () -> Resting,
        to action: @escaping (CGFloat) -> Void,
    ) -> some View {
        background(alignment: .top) {
            if isOn {
                RestingRailRow(content: resting())
                    // Offered no height, as `RailStack` offers a row, not the grown row's.
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    // Its name is no card's: a held card reads the row's own.
                    .transformPreference(CardMarks.self) { $0 = CardMarks.defaultValue }
                    .onGeometryChange(for: CGFloat.self, of: \.size.height, action: action)
            }
        }
    }
}

/// A row's layout at rest, as `RailRow` lays it out, without the node it draws over its column
/// or the strokes and marks it reports to the rail.
private struct RestingRailRow<Content: View>: View {
    let content: Content
    @ScaledMetric(relativeTo: .body) private var nodeSize = railNodeSize

    var body: some View {
        RailRowLayout(nodeSize: nodeSize) {
            RailNodeColumn()
            content.modifier(RailRowContentFrame())
        }
    }
}
