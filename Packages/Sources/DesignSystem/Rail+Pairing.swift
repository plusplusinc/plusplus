import SwiftUI

// A held row's gap following the card, and the card resting over a plain neighbor to pair with
// it (`RailPairing.swift` holds the rule and its values).

/// The card resting over a plain neighbor: the slot that pairs the two, where the card was when
/// it came to rest, and the countdown to pairing.
struct RailDwell<ID: Hashable> {
    var target: RailSlot<ID>
    var anchor: CGFloat
    var countdown: Task<Void, Never>
}

extension Rail {
    /// Opens the gap where the card would land, and pairs the held row with a plain neighbor the
    /// card rests over. A pair holds while the card stays over its partner, and comes apart, with
    /// the reorder's tick, once it goes back toward its gap or the gap moves.
    func follow(_ id: RowID) {
        guard let held = drag, held.lifted == id, !held.isReleased else { return }
        let rest = data.map(\.id).filter { $0 != id }
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
        countDown(over: held.isOverBar ? nil : pairing(lean: RailDrag.pairLean))
    }

    /// Counts down to pairing with `target` while the card rests over it, starting again when the
    /// card wanders more than `pairSlop`, and stopping when it leaves. A timer, not a wait for
    /// something else to finish: the pair forms because time passed with the card still.
    private func countDown(over target: RailSlot<RowID>?) {
        guard let target else { return endDwell() }
        if let dwell, dwell.target == target, abs(cardTop - dwell.anchor) <= RailDrag.pairSlop {
            return
        }
        endDwell()
        let countdown = Task {
            try? await Task.sleep(for: RailDrag.pairDwell)
            guard !Task.isCancelled else { return }
            pair(target)
        }
        dwell = RailDwell(target: target, anchor: cardTop, countdown: countdown)
    }

    /// Stops any countdown to a pair.
    func endDwell() {
        dwell?.countdown.cancel()
        dwell = nil
    }

    /// Pairs the held row with the neighbor `target` joins: the loop draws around the two, with a
    /// firmer tap than a slot's, and a drop now makes them a group.
    private func pair(_ target: RailSlot<RowID>) {
        dwell = nil
        guard let held = drag, !held.isReleased, !held.isOverBar,
              held.slot == RailSlot(target.place)
        else { return }
        withAnimation(reduceMotion ? nil : RailDrag.gap) {
            drag?.slot = target
            drag?.isPaired = true
        }
        pairs += 1
    }
}
