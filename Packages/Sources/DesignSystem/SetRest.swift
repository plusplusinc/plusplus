import SwiftUI

/// The rest between two sets of the current exercise, which takes the place of its figures
/// (`SetRoom`): "Rest" in a caption's style over the countdown in a figure's, and the bar of its
/// progress under it (`RestProgress`), nothing under the bar, so the bar reads as the countdown's.
/// Logging the set swaps the two on one curve from the tap (`SetMotion.restSwap`): the set's
/// parts fade as they drop a few points, "then rest 1:00" at the caption line's end with them,
/// then the rest's fade in as they rise into place; at the rest's end they swap back the same
/// way. The −15 s and +15 s keys are at the bottom, in the key's place.
public struct SetRest {
    /// Whether the rest is in the slot: from the log until its end.
    public let isRunning: Bool
    /// The rest's length, which the countdown shows before it runs.
    let length: Int
    let ends: Date
    let pausedLeft: Double?
    /// Over, and swapping back: the countdown reads 0:00 and holds still as it goes, never
    /// rolling its last figure.
    let isOver: Bool
    /// Whether a + or − turns the countdown's figure: once it is up. Turning as it came in, its
    /// end set at the log, it rolled from its length to itself.
    let turns: Bool
    /// What waits in the slot: a rest, a timed set's "Starts in", or the set's own count.
    let kind: Kind

    /// What a wait in the figures' slot is.
    public enum Kind: Equatable, Sendable {
        /// "Rest" over the countdown, over its bar.
        case rest
        /// "Starts in" over the short count, over the set's time in words ("30 seconds") in the
        /// bar's place.
        case startsIn(time: String)
        /// A timed set's own count where the figures stand, with no word over it and no bar.
        case count
    }

    public init(
        isRunning: Bool,
        length: Int,
        ends: Date = .distantPast,
        pausedLeft: Double? = nil,
        isOver: Bool = false,
        turns: Bool = false,
        kind: Kind = .rest,
    ) {
        self.kind = kind
        self.isRunning = isRunning
        self.length = length
        self.ends = ends
        self.pausedLeft = pausedLeft
        self.isOver = isOver
        self.turns = turns
    }

    /// The rest as VoiceOver reads it while it runs: its own element after the exercise's label,
    /// which holds every other part of the current exercise as one, "Rest", its time left as its
    /// value, changing as the countdown does. Nothing before it runs, or once it is over.
    public var spoken: some View {
        SpokenRest(block: block)
            .opacity(isRunning && !isOver ? 1 : 0)
            .accessibilityHidden(!isRunning || isOver)
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

/// The current exercise's figures slot, the same height during a set and during a rest between
/// sets: during a set, the figures and their captions over the bar's place, empty; during a rest,
/// "Rest" over the countdown, its line in place of the captions', over its bar
/// (`RestProgress`). Nothing is under the bar. "Rest" starts where the figures do, its capitals'
/// tops at theirs, and the countdown stands a line lower than the figures, which the swap's fade
/// and rise carry, the figures gone before it shows. The number row is as tall as the taller of
/// its two states, so nothing below moves as they swap. An exercise with no rest between its sets
/// has no bar's place.
///
/// `swap` runs from 0, the set up, to 1, the rest up, on the row's animation, and each part's fade
/// and rise is worked out from it, so the two swap as one move on its curve, the one going gone
/// before the one coming shows.
struct SetRoom: View, Animatable {
    let figures: [RowFocus.Figure]
    let rest: SetRest?
    var swap: CGFloat

    @ScaledMetric(relativeTo: CurrentFigure.textStyle) private var size = CurrentFigure.size
    /// `ppFigureCaption`'s point size, the body style's at the default size.
    @ScaledMetric(relativeTo: .body) private var captionSize: CGFloat = 17
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(figures: [RowFocus.Figure], rest: SetRest?) {
        self.figures = figures
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
                        // Its capitals' tops where the figures' are, as far under the caption
                        // line, not the font's room over them lower.
                        if let word = Self.word(rest.kind) {
                            Text(word)
                                .font(.ppFigureCaption)
                                .foregroundStyle(.pp(.textSecondary))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, -Self.overCapitals(size: captionSize))
                        }
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
            if let rest, let block {
                switch rest.kind {
                case .rest:
                    block.progress
                        .padding(.top, Spacing.md)
                        .opacity(coming)
                case let .startsIn(time):
                    Text(time)
                        .font(.ppFigureCaption)
                        .foregroundStyle(.pp(.textSecondary))
                        .padding(.top, Spacing.sm)
                        .opacity(coming)
                case .count:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The word over the countdown: none over a timed set's own count.
    private static func word(_ kind: SetRest.Kind) -> LocalizedStringKey? {
        switch kind {
        case .rest: "Rest"
        case .startsIn: "Starts in"
        case .count: nil
        }
    }

    /// The room a line of the system font at `size` leaves over its capitals.
    static func overCapitals(size: CGFloat) -> CGFloat {
        #if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: size)
        return font.ascender - font.capHeight
        #else
        return 0
        #endif
    }

    /// Where in the swap the figures have gone and the rest starts to come in, or back.
    static let handOff: CGFloat = 0.4
}

/// A part of the set outside the figures slot, "then rest 1:00" at the caption line's end, going
/// as the rest comes in and back as it ends, on the slot's own fade and drop, so it leaves with
/// the figures. `swap` as `SetRoom`'s.
struct SetRoomGoing: ViewModifier, Animatable {
    var swap: CGFloat

    init(isResting: Bool) {
        swap = isResting ? 1 : 0
    }

    var animatableData: CGFloat {
        get { swap }
        set { swap = newValue }
    }

    func body(content: Content) -> some View {
        content.going(RestRoomFade.fade(swap, from: 0, width: SetRoom.handOff))
    }
}

extension View {
    /// A part of the set going as the rest comes in, `going` from 0 to 1: fading as it drops.
    fileprivate func going(_ going: CGFloat) -> some View {
        opacity(1 - going).offset(y: going * SetMotion.arriveRise)
    }

    /// A part of the rest coming in, `coming` from 0 to 1: fading in as it rises into place.
    func coming(_ coming: CGFloat) -> some View {
        opacity(coming).offset(y: (1 - coming) * SetMotion.arriveRise)
    }
}

/// A part's fade over a change from 0 to 1: 0 until `start`, 1 `width` later.
enum RestRoomFade {
    static func fade(_ share: CGFloat, from start: CGFloat, width: CGFloat) -> CGFloat {
        min(max((share - start) / width, 0), 1)
    }
}
