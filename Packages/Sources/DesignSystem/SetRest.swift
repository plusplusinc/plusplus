import SwiftUI

/// The rest between two sets of the current exercise, which takes the place of its figures
/// (`SetRoom`): "Rest" in a caption's style over the countdown in a figure's, gray while paused.
/// Logging the set swaps the two on one curve from the tap (`SetMotion.restSwap`): the set's
/// parts fade as they drop a few points, "then rest 1:00" at the caption line's end with them,
/// then the rest's fade in as they rise into place; at the rest's end they swap back the same
/// way. Skip rest, filling, and +15 s are at the bottom, in the key's place (`CountKeys`).
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
    /// Whether each second and +15 s turn the countdown's figure: once it is up. Turning as it
    /// came in, its end set at the log, it rolled from its length to itself.
    let turns: Bool
    /// What waits in the slot: a rest, a timed set's "Starts in", or the set's own count.
    public let kind: Kind
    /// Held by a pause: the count takes the gray the workout's paused time does, and its white
    /// back on resume. A count held by its log, as between a side plank's sides, stays white.
    let isPaused: Bool

    /// Whether a rest runs in the slot: "then rest 1:00" goes for a rest only, and stays through
    /// "Starts in" and a set's count, as through a reps set.
    var isResting: Bool {
        isRunning && kind == .rest
    }

    /// Whether the set's segment is green, as the set is under way: not through a rest, nor
    /// through a timed set's "Starts in", but while its count runs, and held where its log
    /// stopped it until the segment turns purple.
    var isOnSet: Bool {
        switch kind {
        case .rest: !isRunning
        case .startsIn: false
        case .count: true
        }
    }

    /// "starts in 10 seconds", for the exercise's label during "Starts in"; nil otherwise.
    var spokenStartsIn: String? {
        guard case .startsIn = kind else { return nil }
        return String(localized: "starts in \(length) seconds")
    }

    /// What a wait in the figures' slot is.
    public enum Kind: Equatable, Sendable {
        /// "Rest" over the countdown.
        case rest
        /// "Starts in" over the short count, nothing under it: the set's time in words ("30
        /// seconds") is at the caption line's end. `time` is for VoiceOver.
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
        isPaused: Bool = false,
    ) {
        self.kind = kind
        self.isPaused = isPaused
        self.isRunning = isRunning
        self.length = length
        self.ends = ends
        self.pausedLeft = pausedLeft
        self.isOver = isOver
        self.turns = turns
    }

    /// The wait as VoiceOver reads it while it runs: its own element after the exercise's label,
    /// which holds every other part of the current exercise as one, "Rest", "Starts in", or, for
    /// a timed set's own count, "Time left", its time left as its value, changing as the
    /// countdown does. Nothing before it runs, or once it is over.
    public var spoken: some View {
        SpokenRest(block: block, label: kind.spokenAs, shown: kind.shown(length: length))
            .opacity(isRunning && !isOver ? 1 : 0)
            .accessibilityHidden(!isRunning || isOver)
    }

    /// The rest as a block, for its countdown: unseen before it runs, its length on the
    /// countdown, so it comes in on its time.
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
/// sets: during a set, the figures and their captions; during a rest, "Rest" over the countdown,
/// its line in place of the captions', over an unseen caption's line, as under every wait's
/// countdown. There is no bar: Skip rest fills instead. "Rest" starts where the figures do, its
/// capitals' tops at theirs, and the countdown stands a line lower than the figures, which the
/// swap's fade and rise carry, the figures gone before it shows. The number row is as tall as the
/// taller of its two states, so nothing below moves as they swap.
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
                    // A wait of one kind giving way to another ("Starts in" reaching 0, a rest
                    // ending on a timed set's count) swaps as the figures and a rest do.
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        // Its capitals' tops where the figures' are, as far under the caption
                        // line, not the font's room over them lower.
                        // Over a timed set's own count, unseen, so the count stands where
                        // "Starts in"'s did and nothing below moves between them.
                        Text(Self.word(rest.kind) ?? "Starts in")
                            .font(.ppFigureCaption)
                            .foregroundStyle(.pp(.textSecondary))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, -Self.overCapitals(size: captionSize))
                            .opacity(Self.word(rest.kind) == nil ? 0 : 1)
                            .accessibilityHidden(Self.word(rest.kind) == nil)
                        // With Reduce Motion the figure changes at once.
                        WaitCountdown(
                            block: block,
                            size: size,
                            turns: rest.turns && !reduceMotion,
                            color: rest.isPaused ? .textSecondary : .textPrimary,
                            shown: rest.kind.shown(length: rest.length),
                        )
                        .figureBox(size: size)
                    }
                    .id(rest.kind.swapID)
                    .transition(Self.kindSwap)
                    .coming(coming)
                }
            }
            if rest != nil {
                // Under every wait's countdown, a caption's line, unseen, so a timed exercise's
                // slot stays one height as its rest gives way to its count.
                Text(verbatim: " ")
                    .font(.ppFigureCaption)
                    .padding(.top, Spacing.sm)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One wait giving way to another in the slot: the one going fades as it drops, over the
    /// swap's first part, then the one coming fades in as it rises, on the change's own curve
    /// (`SetMotion.restSwap`), as the figures and a rest swap.
    private static var kindSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: KindSwap(swap: 0, isComing: true),
                identity: KindSwap(swap: 1, isComing: true),
            ),
            removal: .modifier(
                active: KindSwap(swap: 1, isComing: false),
                identity: KindSwap(swap: 0, isComing: false),
            ),
        )
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

/// A wait going or coming in the figures' slot as another kind takes its place, `swap` from 0 to
/// 1, its fade and drop or rise worked out as `SetRoom`'s are.
private struct KindSwap: ViewModifier, Animatable {
    var swap: CGFloat
    let isComing: Bool

    var animatableData: CGFloat {
        get { swap }
        set { swap = newValue }
    }

    func body(content: Content) -> some View {
        if isComing {
            content.coming(RestRoomFade.fade(
                swap,
                from: SetRoom.handOff,
                width: 1 - SetRoom.handOff,
            ))
        } else {
            content.going(RestRoomFade.fade(swap, from: 0, width: SetRoom.handOff))
                // Going, its count holds where it stood: still ticking, "Starts in" cut short by
                // "Start now" read one second less as it went.
                .environment(\.waitLeaves, swap > 0)
        }
    }
}

/// A wait's countdown in the figures' slot, held where it stood once it is going
/// (`waitLeaves`).
private struct WaitCountdown: View {
    let block: RestBlock
    let size: CGFloat
    let turns: Bool
    let color: ColorToken
    let shown: ClosedRange<Double>

    @Environment(\.locale) private var locale
    @Environment(\.waitLeaves) private var leaves
    @State private var leftAt: Date?

    var body: some View {
        (leaves ? block.holding(at: leftAt ?? .now) : block)
            .countdown(
                size: size,
                locale: locale,
                turns: turns,
                color: color,
                shown: shown,
            )
            .onChange(of: leaves, initial: true) {
                leftAt = leaves ? .now : nil
            }
            // Read by its own element, named for its kind (`SetRest.spoken`), never as "Rest".
            .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    /// Whether a wait in the figures' slot is going, as another kind takes its place.
    @Entry var waitLeaves = false
}

extension SetRest.Kind {
    /// The seconds left a countdown of this kind shows, `length` long. "Starts in" reads 0:01
    /// through its last second until it goes, never 0:00; and at most its length, as it counts
    /// from after the slot has come in, so its 0:10 shows a full second at full strength.
    func shown(length: Int) -> ClosedRange<Double> {
        if case .startsIn = self {
            0.001 ... Double(length)
        } else {
            0 ... .infinity
        }
    }

    /// What VoiceOver calls the countdown: a set's own count is read as the time it has left,
    /// never as a rest.
    var spokenAs: LocalizedStringKey {
        switch self {
        case .rest: "Rest"
        case .startsIn: "Starts in"
        case .count: "Time left"
        }
    }

    /// Which wait this is in the slot: a change swaps one for the other.
    var swapID: Int {
        switch self {
        case .rest: 0
        case .startsIn: 1
        case .count: 2
        }
    }
}

/// A part of the set outside the figures slot, "then rest 1:00" at the caption line's end, going
/// as the rest comes in and back as it ends, on the slot's own fade, in place: words at the line's
/// end never move or cross the words beside them. `swap` as `SetRoom`'s.
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
        content.opacity(1 - RestRoomFade.fade(swap, from: 0, width: SetRoom.handOff))
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

/// A part's fade over a change from 0 to 1: 0 until `start`, 1 `width` later, and whole by the
/// change's end however late `start` is.
enum RestRoomFade {
    static func fade(_ share: CGFloat, from start: CGFloat, width: CGFloat) -> CGFloat {
        min(max((share - min(start, 1 - width)) / width, 0), 1)
    }
}
