import SwiftUI

/// The rest between two sets of the current exercise, which takes the figures' slot
/// (`RowLabel`'s `setRest`) at the same size: the countdown in a figure's style with "rest" as its
/// caption, the bar of its progress under it (`RestProgress`), and the next set on a line under
/// that, "Next: 10 reps · 25 lb/side", wrapping rather than cut short. Logging the set swaps the
/// two in the slot on one curve from the tap (`SetMotion.restSwap`): the figures fade as they drop
/// a few points, then the rest fades in as it rises into place; at the rest's end they swap back
/// the same way. The slot is as tall as the taller of the two through every set, the rest laid
/// out unseen while the figures show, so nothing below it moves as they swap. The −15 s and
/// +15 s keys are at the bottom, in the key's place.
public struct SetRest {
    /// Whether the rest is in the slot: from the log until its end.
    public let isRunning: Bool
    /// The rest's length, which the countdown shows before it runs.
    let length: Int
    /// The next set, on the line under the bar: "Next: 10 reps".
    let next: String
    let ends: Date
    let pausedLeft: Double?
    /// Over, and swapping back: the countdown reads 0:00 and holds still as it goes, never
    /// rolling its last figure.
    let isOver: Bool
    /// Whether a + or − turns the countdown's figure: once it is up. Turning as it came in, its
    /// end set at the log, it rolled from its length to itself.
    let turns: Bool

    public init(
        isRunning: Bool,
        length: Int,
        next: String = "",
        ends: Date = .distantPast,
        pausedLeft: Double? = nil,
        isOver: Bool = false,
        turns: Bool = false,
    ) {
        self.isRunning = isRunning
        self.length = length
        self.next = next
        self.ends = ends
        self.pausedLeft = pausedLeft
        self.isOver = isOver
        self.turns = turns
    }

    /// The rest as a block, for its countdown and bar: unseen before it runs, its length on the
    /// countdown and the bar empty, so it comes in on its time.
    var block: RestBlock {
        RestBlock(
            stage: isRunning ? .open : .none,
            length: length,
            ends: ends,
            pausedLeft: isOver ? 0 : pausedLeft,
        )
    }
}

/// The figures' slot with the rest between sets: `swap` runs from 0, the figures up, to 1, the
/// rest up, on the row's animation, and each part's fade and rise is worked out from it, so the
/// two swap as one move on its curve, the one going gone before the one coming shows.
struct SetRoom: View, Animatable {
    let figures: [RowFocus.Figure]
    let rest: SetRest
    var swap: CGFloat

    @ScaledMetric(relativeTo: CurrentFigure.textStyle) private var size = CurrentFigure.size
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(figures: [RowFocus.Figure], rest: SetRest) {
        self.figures = figures
        self.rest = rest
        swap = rest.isRunning ? 1 : 0
    }

    var animatableData: CGFloat {
        get { swap }
        set { swap = newValue }
    }

    var body: some View {
        let going = RestRoomFade.fade(swap, from: 0, width: Self.handOff)
        let coming = RestRoomFade.fade(swap, from: Self.handOff, width: 1 - Self.handOff)
        let block = rest.block
        ZStack(alignment: .topLeading) {
            CurrentFigures(figures: figures)
                .opacity(1 - going)
                .offset(y: going * SetMotion.arriveRise)
            VStack(alignment: .leading, spacing: 0) {
                FigureStack(caption: String(localized: "rest")) {
                    // With Reduce Motion the figure changes at once.
                    block.countdown(size: size, locale: locale, turns: rest.turns && !reduceMotion)
                        .figureBox(size: size)
                }
                block.progress
                    .padding(.top, Spacing.md)
                Text(AttributedString.monoNumbers(rest.next, font: .ppCurrentProgress))
                    .font(.ppCurrentProgress)
                    .foregroundStyle(.pp(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.sm)
            }
            .opacity(coming)
            .offset(y: (1 - coming) * SetMotion.arriveRise)
            .accessibilityHidden(!rest.isRunning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Where in the swap the figures have gone and the rest starts to come in, or back.
    static let handOff: CGFloat = 0.4
}

/// A part's fade over a change from 0 to 1: 0 until `start`, 1 `width` later.
enum RestRoomFade {
    static func fade(_ share: CGFloat, from start: CGFloat, width: CGFloat = 0.3) -> CGFloat {
        min(max((share - start) / width, 0), 1)
    }
}
