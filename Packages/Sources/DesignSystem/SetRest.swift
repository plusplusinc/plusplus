import SwiftUI

/// The rest between two sets of the current exercise, which takes the place of the set's numbers
/// (`RowLabel`'s `setRest`). During a set with a rest after it, the coming rest shows as a quiet
/// line under the numbers, "Rest 0:45", as the rest before the next exercise does
/// (`RestBlock.Stage.line`). Logging the set swaps the two in one move: the line grows up into
/// the numbers' place, "Rest" rising whole as the countdown grows in under it and −15 s and
/// +15 s come in, with the rest's progress bar between the two (`RestProgress`), while the
/// numbers shrink down into the line's place, where they read as the next set, "Set 2: 10 reps".
/// The rail beside them is as with no rest. At the rest's end they swap back. The room for the
/// numbers is as tall as
/// the numbers, the rest fitting in it and the gap under it, and the line's room stays through
/// the last set, so nothing below it moves and the row is no taller for its rests.
public struct SetRest {
    public enum Stage: Sendable {
        /// The exercise rests between its sets, but not after this one: the room is held, and
        /// the line under it is the rest before the next exercise's, if any (`RestBlock`).
        case held
        /// A rest will follow this set: the quiet line under the numbers.
        case coming
        /// The rest is running in the numbers' place, the next set in the line's.
        case running
    }

    public let stage: Stage
    /// The coming rest's length, which its line shows; nil for none.
    let length: Int?
    /// The next set in the line's place during the rest: "Set 2: 10 reps".
    let next: String
    let ends: Date
    let pausedLeft: Double?
    /// Over, and swapping back: the countdown reads 0:00 and holds still as it goes, never
    /// rolling its last figure, and the keys still take taps, doing nothing, so one aimed at a key
    /// as the rest ends never falls through to the row and opens its sheet.
    let isOver: Bool
    let onShorten: () -> Void
    let onExtend: () -> Void

    public init(
        stage: Stage,
        length: Int?,
        next: String = "",
        ends: Date = .distantPast,
        pausedLeft: Double? = nil,
        isOver: Bool = false,
        onShorten: @escaping () -> Void = { },
        onExtend: @escaping () -> Void = { },
    ) {
        self.isOver = isOver
        self.stage = stage
        self.length = length
        self.next = next
        self.ends = ends
        self.pausedLeft = pausedLeft
        self.onShorten = onShorten
        self.onExtend = onExtend
    }

    var block: RestBlock {
        RestBlock(
            stage: .open,
            length: length ?? 0,
            ends: ends,
            pausedLeft: isOver ? 0 : pausedLeft,
            onShorten: onShorten,
            onExtend: onExtend,
        )
    }
}

/// The numbers' room with the rest between sets: `swap` runs from 0, the set's numbers up, to 1,
/// the rest up, on the row's animation, and every part's place, size, and fade is worked out from
/// it, so the two cross as one move on its curve.
struct SetRoom: View, Animatable {
    let figures: [RowFocus.Figure]
    let rest: SetRest
    var swap: CGFloat

    @ScaledMetric(relativeTo: CurrentFigure.textStyle) private var size = RestFigure.size
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(figures: [RowFocus.Figure], rest: SetRest) {
        self.figures = figures
        self.rest = rest
        swap = rest.stage == .running ? 1 : 0
    }

    var animatableData: CGFloat {
        get { swap }
        set { swap = newValue }
    }

    var body: some View {
        let hasLine = rest.stage != .held
        SetRoomLayout(swap: swap, hasLine: hasLine) {
            CurrentFigures(figures: figures)
                .scaleEffect(1 - (1 - Self.shrunk) * swap, anchor: .topLeading)
                // Gone before the rest rising through it has grown, so the two never blur
                // into each other where they cross.
                .opacity(1 - RestRoomFade.fade(swap, from: 0, width: 0.4))
            Text(AttributedString.monoNumbers(rest.next, font: .ppCurrentProgress))
                .font(.ppCurrentProgress)
                .foregroundStyle(.pp(.textSecondary))
                .lineLimit(1)
                .opacity(RestRoomFade.fade(swap, from: 0.6, width: 0.4))
            restLook
                .opacity(hasLine ? 1 : 0)
        }
        // Fading, the keys take no taps, and one aimed at a key as the rest ended fell through to
        // the row and opened its sheet: through the swap back, the room takes it, doing nothing.
        .overlay {
            if rest.isOver {
                Color.clear.contentShape(.rect).onTapGesture { }.accessibilityHidden(true)
            }
        }
    }

    /// The rest, as its line at `swap` 0 and grown at 1: "Rest" whole all the way, the line's
    /// length going first, the countdown growing in under it, then the keys.
    private var restLook: some View {
        let countdown = RestRoomFade.fade(swap, from: 0.4, width: 0.45)
        // Last in and first out: going, they would cross the next set's line coming up.
        let keys = RestRoomFade.fade(swap, from: 0.7, width: 0.3)
        let block = rest.block
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Rest")
                Text(AttributedString.monoNumbers(
                    " " + RestBlock.text(Double(rest.length ?? 0), locale: locale),
                    font: .ppCurrentProgress,
                ))
                .opacity(rest.length == nil ? 0 : 1 - RestRoomFade.fade(swap, from: 0, width: 0.3))
            }
            .font(.ppCurrentProgress)
            .foregroundStyle(.pp(.textSecondary))
            // With no rest to come, the line goes as the numbers come back.
            .opacity(rest.length == nil ? swap : 1)
            // With Reduce Motion the figure changes at once: rolling, it came up turning from 0:00
            // to the rest's length, with no swap to hide it.
            block.countdown(size: size, locale: locale, turns: !rest.isOver && !reduceMotion)
                .scaleEffect(Self.grown + (1 - Self.grown) * countdown, anchor: .topLeading)
                .opacity(countdown)
            block.progress
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.sm)
                .opacity(countdown)
            block.buttons
                .opacity(keys)
                .offset(y: (1 - keys) * SetMotion.arriveRise)
                .allowsHitTesting(rest.stage == .running)
        }
        .accessibilityHidden(rest.stage != .running)
    }

    /// The numbers' size in the line: about the line's text against the figures'.
    static let shrunk: CGFloat = 0.2
    /// The countdown's size as it starts to grow, against its own: about the line's text.
    static let grown: CGFloat = 0.35
}

/// The numbers' room, as tall as the numbers or the grown rest, and under it, with
/// `hasLine`, the line's room. The numbers and the next set's line travel from the room's top to
/// the line's as `swap` runs to 1; the rest from the line's to the room's top.
private struct SetRoomLayout: Layout {
    let swap: CGFloat
    let hasLine: Bool

    private func metrics(
        _ width: CGFloat?,
        _ subviews: Subviews,
    ) -> (room: CGFloat, line: CGFloat) {
        let offer = ProposedViewSize(width: width, height: nil)
        let heights = subviews.map { $0.sizeThatFits(offer).height }
        let line = heights.count > 1 ? heights[1] : 0
        // As tall as the numbers or the grown rest, whichever is taller, the same through every
        // set, so nothing below moves as they swap. With its progress bar the rest no longer fits
        // in the numbers' height: held to it, the keys overlapped the next set's line.
        let rest = heights.count > 2 ? heights[2] : 0
        return (max(heights.first ?? 0, rest), line)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let (room, line) = metrics(proposal.width, subviews)
        return CGSize(
            width: proposal.width ?? 0,
            height: hasLine ? room + Spacing.sm + line : room,
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let offer = ProposedViewSize(width: bounds.width, height: nil)
        let (room, line) = metrics(bounds.width, subviews)
        let lineY = room + Spacing.sm
        let down = bounds.minY + lineY * swap
        let up = bounds.minY + lineY * (1 - swap)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX, y: index < 2 ? down : up),
                proposal: offer,
            )
        }
    }
}

/// A part's fade over a change from 0 to 1: 0 until `start`, 1 `width` later.
enum RestRoomFade {
    static func fade(_ share: CGFloat, from start: CGFloat, width: CGFloat = 0.3) -> CGFloat {
        min(max((share - start) / width, 0), 1)
    }
}
