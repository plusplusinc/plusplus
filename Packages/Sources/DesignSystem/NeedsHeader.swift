#if os(iOS)
import SwiftUI

/// The heading of the items one piece of equipment short of a filter: "Also needs" in the
/// letter headings' style right before a small button that names the piece and adds it to the
/// filter, "+ Bench" with a green +, the pair at the line's trailing edge so the button ends
/// where Clear does. The words read as a heading that names the piece, "Also needs a bench",
/// since the visible words don't; the button reads "Add bench to Equipment". Where the two
/// won't fit on one line, the button goes under the words, both trailing (`LineOrStack`).
public struct NeedsHeader: View {
    let needed: String
    let addTitle: String
    let onAdd: () -> Void

    /// `needed` is the piece as the heading reads it, "a bench"; `addTitle` as the button
    /// shows it, "Bench".
    public init(needed: String, addTitle: String, onAdd: @escaping () -> Void) {
        self.needed = needed
        self.addTitle = addTitle
        self.onAdd = onAdd
    }

    public var body: some View {
        LineOrStack(atTrailingEdge: true) {
            Text("Also needs")
                .fontWeight(.semibold)
                .foregroundStyle(Color.pp(.textSecondary))
                .accessibilityLabel("Also needs \(needed)")
                .accessibilityAddTraits(.isHeader)
            SmallCapsuleButton(
                systemImage: "plus",
                title: addTitle,
                symbolColor: .accent,
                action: onAdd,
            )
            .accessibilityLabel("Add \(addTitle.lowercased()) to Equipment")
        }
        .font(.ppRowDetail)
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        NeedsHeader(needed: "a bench", addTitle: "Bench") { }
        NeedsHeader(needed: "a balance board", addTitle: "Balance board") { }
    }
    .padding(Spacing.md)
    .background(Color.pp(.background))
}
#endif
