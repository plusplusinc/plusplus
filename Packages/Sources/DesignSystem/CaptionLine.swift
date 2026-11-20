import SwiftUI

/// The current exercise's caption line: its first subview at the leading edge, "Set 1 of 3", and
/// each one after it, "then rest 1:00", at the trailing edge, on one line where both fit with
/// `spacing` between them; else under the first, at the leading edge. Each end subview is placed
/// by its own width, so words that fit stay on the line even where wider words the line keeps
/// room for (hidden subviews) would not; the line is as tall as its tallest end needs.
struct CaptionLine: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        frames(proposal.width, subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let frames = frames(bounds.width, subviews)
        for (subview, (origin, offer)) in zip(subviews, frames.placed) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: offer,
            )
        }
    }

    private func frames(
        _ width: CGFloat?,
        _ subviews: Subviews,
    ) -> (placed: [(CGPoint, ProposedViewSize)], size: CGSize) {
        guard let lead = subviews.first else { return ([], .zero) }
        let ends = subviews.dropFirst()
        let endSizes = ends.map { $0.sizeThatFits(.unspecified) }
        let leadIdeal = lead.sizeThatFits(.unspecified)
        let width = width ?? (leadIdeal.width + spacing + (endSizes.map(\.width).max() ?? 0))
        let fits = endSizes.map { leadIdeal.width + spacing + $0.width <= width }
        let full = ProposedViewSize(width: width, height: nil)
        // The lead keeps clear of the widest end beside it; with none beside it, the whole line.
        let besideWidth = zip(endSizes, fits).filter(\.1).map(\.0.width).max()
        let leadOffer = besideWidth
            .map { ProposedViewSize(width: width - spacing - $0, height: nil) }
            ?? full
        let leadHeight = lead.sizeThatFits(leadOffer).height
        let leadFullHeight = lead.sizeThatFits(full).height
        var placed = [(CGPoint.zero, leadOffer)]
        var height = leadHeight
        for (end, (size, fit)) in zip(ends, zip(endSizes, fits)) {
            if fit {
                placed.append((CGPoint(x: width - size.width, y: 0), .unspecified))
                height = max(height, size.height)
            } else {
                placed.append((CGPoint(x: 0, y: leadFullHeight), full))
                height = max(height, leadFullHeight + end.sizeThatFits(full).height)
            }
        }
        return (placed, CGSize(width: width, height: height))
    }
}

/// The words at the caption line's end, "then rest 1:00", "30 seconds", or "last set": laid out
/// through a rest too, faded, so the line keeps its height, and with the widest words it keeps
/// room for (`RowFocus.afterRoom`) laid out unseen, so the line is as tall in each of a set's
/// states: "30 seconds" stays beside "Round 1 of 3 · Left" where "then rest 0:30" will wrap
/// under it, and the line holds that second line's height throughout. Words that change fade in
/// place, the old gone before the new show, never legible together, both within the slot's swap
/// (`SetMotion.restSwap`, `SetRoom.handOff`); each words a view of their own, so an unseen "then
/// rest" never shows as it gives way. Subviews of `CaptionLine`, after its lead.
struct CaptionEndWords: View {
    let focus: RowFocus
    let isResting: Bool

    var body: some View {
        ForEach(focus.afterRoom, id: \.self) { words in
            text(words).hidden()
        }
        text(focus.after ?? "")
            .opacity(focus.showsAfter ? 1 : 0)
            .modifier(SetRoomGoing(isResting: isResting))
            .id(focus.after)
            .transition(Self.change)
    }

    private func text(_ words: String) -> some View {
        Text(AttributedString.monoNumbers(words, font: .ppCurrentProgress))
            .font(.ppCurrentProgress)
            .foregroundStyle(.pp(.textSecondary))
    }

    /// The old words fade over the swap's first part, the new over the next, as the figures
    /// and a wait swap.
    private static var change: AnyTransition {
        let part = SetMotion.roll * SetRoom.handOff
        return .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: part).delay(part)),
            removal: .opacity.animation(.easeIn(duration: part)),
        )
    }
}
