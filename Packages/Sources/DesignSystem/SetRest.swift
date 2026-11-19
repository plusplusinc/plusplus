import SwiftUI

/// The rest between two sets of the current exercise, which takes the place of its figures and
/// the line under them (`SetRoom`), line for line: "Rest" in a caption's style over the countdown
/// in a figure's, the bar of its progress under it (`RestProgress`), and the next set on the
/// quiet line, "Next: set 2 · 10 reps · 25 lb/side", wrapping rather than cut short. Logging the
/// set swaps
/// the two on one curve from the tap (`SetMotion.restSwap`): the set's parts fade as they drop a
/// few points, then the rest's fade in as they rise into place; at the rest's end they swap back
/// the same way. The −15 s and +15 s keys are at the bottom, in the key's place.
public struct SetRest {
    /// Whether the rest is in the slot: from the log until its end.
    public let isRunning: Bool
    /// The rest's length, which the countdown shows before it runs.
    let length: Int
    /// The next set, on the line under the bar: "Next: set 2 · 10 reps".
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

/// The current exercise's figures and what follows them, the same shape during a set and during
/// a rest between sets, line for line: the number row and its caption, the bar's place, and one
/// quiet line. During a set, the figures, the bar's place empty, and what follows the set, "then
/// rest 1:00", "last set", or nothing; during a rest, "Rest" over the countdown, its line in place
/// of the caption's, its bar (`RestProgress`), and the next set, "Next: set 2 · 10 reps · 25
/// lb/side". The countdown stands a line lower than the figures, which the swap's fade and rise
/// carry, the figures gone before it shows. Each line is as tall as the
/// taller of its two states, the one not showing laid out unseen, wrapping included, so nothing
/// below moves as they swap. An exercise with no rest between its sets has no bar's place.
///
/// `swap` runs from 0, the set up, to 1, the rest up, on the row's animation, and each part's fade
/// and rise is worked out from it, so the two swap as one move on its curve, the one going gone
/// before the one coming shows.
struct SetRoom: View, Animatable {
    let figures: [RowFocus.Figure]
    let after: String?
    let rest: SetRest?
    var swap: CGFloat

    @ScaledMetric(relativeTo: CurrentFigure.textStyle) private var size = CurrentFigure.size
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(figures: [RowFocus.Figure], after: String?, rest: SetRest?) {
        self.figures = figures
        self.after = after
        self.rest = rest
        swap = rest?.isRunning == true ? 1 : 0
    }

    var animatableData: CGFloat {
        get { swap }
        set { swap = newValue }
    }

    var body: some View {
        let going = RestRoomFade.fade(swap, from: 0, width: Self.handOff)
        let coming = RestRoomFade.fade(swap, from: Self.handOff, width: 1 - Self.handOff)
        let block = rest?.block
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                CurrentFigures(figures: figures)
                    .going(going)
                if let rest, let block {
                    // "Rest" over the countdown, as over the rest between exercises: its line
                    // takes the place of the caption's under the figures.
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Rest")
                            .font(.ppFigureCaption)
                            .foregroundStyle(.pp(.textSecondary))
                            .fixedSize(horizontal: false, vertical: true)
                        // With Reduce Motion the figure changes at once.
                        block.countdown(
                            size: size,
                            locale: locale,
                            turns: rest.turns && !reduceMotion,
                        )
                        .figureBox(size: size)
                    }
                    .coming(coming)
                }
            }
            if let block {
                block.progress
                    .padding(.top, Spacing.md)
                    .opacity(coming)
            }
            ZStack(alignment: .topLeading) {
                // One line's room even when nothing follows the set, so the line coming in
                // later, as "last set", moves nothing below.
                quietLine("0").hidden()
                quietLine(after ?? "")
                    .going(going)
                if let rest {
                    quietLine(rest.next)
                        .coming(coming)
                }
            }
            .padding(.top, Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quietLine(_ text: String) -> some View {
        Text(AttributedString.monoNumbers(text, font: .ppCurrentProgress))
            .font(.ppCurrentProgress)
            .foregroundStyle(.pp(.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Where in the swap the figures have gone and the rest starts to come in, or back.
    static let handOff: CGFloat = 0.4
}

extension View {
    /// A part of the set going as the rest comes in, `going` from 0 to 1: fading as it drops.
    fileprivate func going(_ going: CGFloat) -> some View {
        opacity(1 - going).offset(y: going * SetMotion.arriveRise)
    }

    /// A part of the rest coming in, `coming` from 0 to 1: fading in as it rises into place.
    fileprivate func coming(_ coming: CGFloat) -> some View {
        opacity(coming).offset(y: (1 - coming) * SetMotion.arriveRise)
    }
}

/// A part's fade over a change from 0 to 1: 0 until `start`, 1 `width` later.
enum RestRoomFade {
    static func fade(_ share: CGFloat, from start: CGFloat, width: CGFloat = 0.3) -> CGFloat {
        min(max((share - start) / width, 0), 1)
    }
}
