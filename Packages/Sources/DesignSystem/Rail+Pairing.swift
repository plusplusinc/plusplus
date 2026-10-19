import SwiftUI

// A held row's gap following the card, and the card resting over a plain neighbor to pair with
// it (`RailPairing.swift` holds the rule and its values).

extension Rail {
    /// Opens the gap where the card would land, and pairs the held row with a plain neighbor the
    /// card rests over. A pair holds while the card stays over its partner, and comes apart, with
    /// the reorder's tick, once it goes back toward its gap or the gap moves.
    func follow(_ id: RowID) {
        guard let held = drag, held.lifted == id, !held.isReleased else { return }
        let rest = data.map(\.id).filter { $0 != id }
        let leaving = restGroup(of: id).subtracting([id])
        let plain = held.isPaired ? RailSlot(held.slot.place) : held.slot
        let slot = RailDrag.candidate(for: cardTop, in: candidates(lifting: id), current: plain)
        let gap = gapTop(lifting: id, at: slot) ?? cardTop
        func pairing(lean: CGFloat) -> RailSlot<RowID>? {
            RailDrag.pairing(
                cardTop: cardTop,
                gapTop: gap,
                slot: slot,
                rest: rest,
                groups: groups,
                leaving: leaving,
                lean: lean,
            )
        }
        if held.isPaired, slot == plain, pairing(lean: RailDrag.pairRelease) == held.slot {
            return
        }
        if slot != held.slot {
            withAnimation(reduceMotion ? nil : RailDrag.gap) {
                drag?.slot = slot
                drag?.isPaired = false
            }
            // Over a bar the rows don't show the slot, so its changes aren't felt either.
            if !held.isOverBar {
                ticks += 1
            }
        }
        dwell = RailDrag.dwell(
            dwell,
            over: held.isOverBar ? nil : pairing(lean: RailDrag.pairLean),
            cardTop: cardTop,
        )
    }

    /// Waits out the card's rest over a plain neighbor, then pairs the two. Run as the rail's
    /// `.task(id: dwell)`, so a new rest, or none, cancels it, as does the rail going away. A
    /// timer, not a wait for something else to finish: the pair forms because time passed with
    /// the card still, and a still finger sends no event to check against.
    func countDown() async {
        guard let dwell, await (try? Task.sleep(for: RailDrag.pairDwell)) != nil else { return }
        pair(dwell.target)
    }

    /// Pairs the held row with the neighbor `target` joins: the loop draws around the two, with a
    /// firmer tap than a slot's, and a drop now makes them a group.
    private func pair(_ target: RailSlot<RowID>) {
        dwell = nil
        guard let held = drag, !held.isReleased, !held.isOverBar,
              held.slot == RailSlot(target.place)
        else { return }
        let gap = gapTop(lifting: held.lifted, at: target) ?? cardTop
        withAnimation(reduceMotion ? nil : RailDrag.gap) {
            drag?.slot = target
            drag?.isPaired = true
            drag?.shift = abs(cardTop - gap)
        }
        pairs += 1
    }

    /// While a rest has paired the held row with a neighbor, which side the partner shows on.
    private var shownPair: RailNeighbor? {
        guard let drag, drag.isPaired, !drag.isReleased, !drag.isOverBar else { return nil }
        return drag.slot.joining
    }

    /// How far each row moves, and the end view, so the partner of a pair sits clear of the card
    /// and its name reads in full: the partner and every row past it, by the drag's `shift`,
    /// down for a partner below, with the end view, and up for one above.
    func pairShifts(_ ids: [RowID]) -> (rows: [RowID: CGFloat], end: CGFloat) {
        guard let drag, let joining = shownPair else { return ([:], 0) }
        guard let gap = ids.firstIndex(of: drag.lifted) else { return ([:], 0) }
        let moved = joining == .below ? ids.suffix(from: gap + 1) : ids.prefix(gap)
        let shift = joining == .below ? drag.shift : -drag.shift
        let rows = Dictionary(moved.map { ($0, shift) }) { first, _ in first }
        return (rows, joining == .below ? shift : 0)
    }

    /// While dropping the held row would leave it in a superset, that superset as it shows: its
    /// rows where they are drawn, the held row's at the card's top, `cardY`, not at its gap, so
    /// the well wraps the card with no empty strip beside it, reaching past the card where it is
    /// an end. As the card settles, it takes the look of the rows' place, fading as it goes.
    /// Nil over a bar, when the drop would leave the row on its own, or until the rows have
    /// reported their nodes.
    func heldWell(_ drag: RailDragState<RowID>, cardY: CGFloat) -> HeldWell? {
        guard !drag.isOverBar else { return nil }
        let rows = shownRows.map(\.id)
        let groups = RailDrag.groups(rows, joined: shownJoined)
        guard let group = groups[drag.lifted] else { return nil }
        let shifts = pairShifts(rows).rows
        let heights = heights.byID
        var tops: [RowID: CGFloat] = [:]
        var y: CGFloat = 0
        for id in rows {
            tops[id] = y
            y += heights[id] ?? 0
        }
        let others = rows.filter { groups[$0] == group && $0 != drag.lifted }
        let top = { (id: RowID) in (tops[id] ?? 0) + (shifts[id] ?? 0) }
        let cardBottom = cardY + (heights[drag.lifted] ?? 0)
        guard let key = others.first,
              let first = others.map(top).min(),
              let last = others.map({ top($0) + (heights[$0] ?? 0) }).max()
        else { return nil }
        // Let go, the card settles into its gap as a row, and the well into the rows' place as it
        // fades.
        let card = drag.isReleased ? WellCard() : WellCard(
            top: cardY <= first ? cardY : nil,
            bottom: cardBottom >= last ? cardBottom : nil,
        )
        let span = min(first, cardY) ... max(last, cardBottom)
        guard let outline = wellOutline(rows: span, card: card) else { return nil }
        return HeldWell(key: key, outline: outline)
    }
}

/// The well around the held row's superset, as it shows.
struct HeldWell {
    /// Its first row other than the held one, so one well changes shape as the held row moves in
    /// its superset.
    let key: AnyHashable
    let outline: WellOutline
}
