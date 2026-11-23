import SwiftUI

/// A row's name over an optional detail line, given in parts. With no parts there is no line at
/// all, not an empty one. VoiceOver reads it as one element, "name, detail", with the detail in
/// words when `spokenDetail` is given.
///
/// Given a `focus`, it is the current exercise of a workout: the name grows large, and the detail
/// gives way to, top to bottom, its sets as a bar of segments (`SetSegments`), a caption line,
/// "Set 1 of 3" (`ProgressLine`) and at its end what follows the set, "then rest 1:00" or "last
/// set" (`CaptionLine`), the plan's figures, large, side by side (`CurrentFigures`, in `SetRoom`),
/// and the exercise's equipment, the label growing to their height. Changed in an animation, the
/// name scales between its two sizes (`GrowingName`), and the parts under it come in, and go, in
/// turn (`SetMotion`).
///
/// A finished exercise (`isDone`) goes quiet: its name in `textSecondary`, its detail in
/// `textTertiary`. The exercise next after a rest between two exercises (`nextUp`) grows a step
/// for the rest's length, its name part of the way to the current exercise's size
/// (`nextGrowth`), its equipment under its detail line.
public struct RowLabel: View {
    private let title: String
    private let detail: [String]
    private let spokenDetail: String?
    private let focus: RowFocus?
    /// How far the exercise is through its sets in a workout, shown as bars at the trailing
    /// end of its detail line, or as segments on the current exercise.
    private let bars: SetProgress?
    /// On the current exercise, the rest between its sets, which takes the figures' slot.
    private let setRest: SetRest?
    private let isDone: Bool
    /// The equipment of the exercise next after the rest running, which grows a step.
    private let nextUp: [String]?

    /// How far the name of the exercise next after a rest grows toward the current exercise's
    /// size: about 22 pt from a row's 17 and the current exercise's 28, as in the drawing picked.
    static let nextGrowth: CGFloat = 5 / 11

    /// The label's height as a row, which its height runs from and back to, so the
    /// label grows and shrinks over the whole animation, on its curve.
    @State private var restingHeight: CGFloat = 0
    /// The label's height as the current exercise, which the height runs from as it shrinks back:
    /// by then its column has given up the parts that made it that tall.
    @State private var grownHeight: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.restingLabelFloor) private var restingLabelFloor
    @Environment(\.exerciseMoveWay) private var exerciseMoveWay

    public init(
        title: String,
        detail: [String],
        spokenDetail: String? = nil,
        focus: RowFocus? = nil,
        bars: SetProgress? = nil,
        setRest: SetRest? = nil,
        isDone: Bool = false,
        nextUp: [String]? = nil,
    ) {
        self.setRest = setRest
        self.isDone = isDone
        self.nextUp = nextUp
        self.title = title
        self.detail = detail
        self.spokenDetail = spokenDetail
        self.focus = focus
        self.bars = bars
    }

    /// A row whose detail is one line, or none.
    public init(title: String, detail: String?) {
        self.init(title: title, detail: detail.map { [$0] } ?? [])
    }

    public var body: some View {
        let detailText = Self.detailText(detail, stacked: dynamicTypeSize.isAccessibilitySize)
        content(detailText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
    }

    /// The name stays where it is as the row grows: the label stands at its height from the start,
    /// from its top, and the equipment and the numbers come in below the name inside it.
    private func content(_ detailText: String?) -> some View {
        StandingHeight(
            growth: focus == nil ? 0 : 1,
            isCurrent: focus != nil,
            // On a rail, a row stands at least as tall as two lines: growing from its own
            // height, the label's first points of growth, and a shrink's last, moved nothing,
            // so the rows below ran ahead of the growth and came back as it ended.
            restingHeight: max(restingHeight, restingLabelFloor),
            grownHeight: grownHeight,
        ) {
            column(detailText)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    if focus == nil {
                        restingHeight = height
                    } else {
                        grownHeight = height
                    }
                }
        }
        // Nothing under the name shows past the height it stands at, so as it opens each part
        // shows only once the rows below have made room for it, and as it closes, a part still
        // going is cut off by its bottom, never over them.
        .clipShape(BottomClip())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func column(_ detailText: String?) -> some View {
        let nameGrowth = focus != nil ? 1 : nextUp != nil ? Self.nextGrowth : 0
        return VStack(alignment: .leading, spacing: Spacing.xxs) {
            GrowingName(
                title: title,
                growth: nameGrowth,
                color: isDone ? .textSecondary : .textPrimary,
            )
            // Out of a workout, a row with no detail has nothing under its name, not even
            // spacing.
            if detailText != nil || focus != nil {
                VStack(alignment: .leading, spacing: focus == nil ? Spacing.sm : Spacing.lg) {
                    // The detail line gives way to the segments and the caption line, in the
                    // same place; a row's bars are at the detail line's trailing end: beside it,
                    // or under it at the accessibility sizes, where beside it eight bars squeezed
                    // the line to nothing.
                    linesAndBars {
                        lines(detailText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let bars, focus == nil {
                            barsOnFirstLine(bars)
                                .part(.progress)
                        }
                    }
                    if let focus {
                        SetRoom(figures: focus.figures, rest: setRest)
                            .part(.figures)
                    }
                    // One view whether next after a rest or current, so the equipment the next
                    // exercise shows through the rest stays as it becomes the current one's.
                    let equipment = focus?.equipment ?? nextUp ?? []
                    if !equipment.isEmpty {
                        Capsules(equipment)
                            .part(.equipment)
                    }
                }
            }
        }
    }

    /// The lines and the bars beside them, or, at the accessibility sizes, the bars under them.
    private var linesAndBars: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: Spacing.xxs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.sm))
    }

    /// The detail line and the progress line, one over the other, as one gives way to the other.
    private func lines(_ detailText: String?) -> some View {
        ZStack(alignment: .topLeading) {
            if let detailText {
                Text(AttributedString.monoNumbers(
                    detailText,
                    font: .ppRowDetailNumber,
                ))
                .font(.ppRowDetail)
                .foregroundStyle(.pp(isDone ? .textTertiary : .textSecondary))
                // Never over the progress line: back once it has gone, and gone as the name
                // starts to grow, before the progress line comes in.
                .opacity(showsDetail ? 1 : 0)
                .animation(
                    showsDetail
                        ? SetMotion.detailIn(way: exerciseMoveWay)
                        // Out of a rest, the next exercise's line stays until the progress line
                        // comes in to take its place.
                        : nextUp != nil ? SetMotion.detailOutOfRest
                        : SetMotion.detailOut(way: exerciseMoveWay),
                    value: showsDetail,
                )
            }
            if let focus {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if let bars {
                        SetSegments(progress: bars, isOnSet: setRest?.isOnSet ?? true)
                    }
                    FocusCaption(focus: focus, isResting: setRest?.isResting == true)
                }
                .padding(.top, Spacing.sm)
                .part(.progress)
            }
        }
    }

    /// Whether the detail line shows: on a row at rest, its name at a row's size.
    private var showsDetail: Bool {
        focus == nil
    }

    /// The bars, centered on the first line of the line beside them: in a box as tall as one line
    /// of its text at every size.
    private func barsOnFirstLine(_ bars: SetProgress) -> some View {
        ZStack {
            Text(verbatim: "0")
                .font(.ppRowDetail)
                .hidden()
            SetBars(bars)
        }
        .fixedSize()
    }

    private var spokenLabel: String {
        let isResting = setRest?.isResting == true
        // A rest's or a set's own count reads as its own element after the label
        // (`SetRest.spoken`), in the figures' place. Landing on "Start in", the label says the
        // set's figures and "start in 5 seconds".
        let startIn = setRest?.spokenStartIn
        let hidesFigures = isResting || setRest?.kind == .count
        let parts = if let focus {
            [
                title,
                // Resting, the caption's "Set 1 of 3 done" says what the bars' words say.
                [
                    isResting && bars != nil ? nil : focus.place.text,
                    focus.showsSide ? focus.side : nil,
                ]
                .compactMap(\.self).joined(separator: ", "),
                hidesFigures ? "" : focus.spokenFigures,
                isResting || startIn != nil || !focus.showsAfter
                    ? "" : focus.spokenAfter ?? focus.after ?? "",
                startIn ?? "",
            ]
        } else {
            [title, spokenDetail ?? detail.joined(separator: ", ")]
        }
        return (parts + [bars?.spoken ?? ""]).filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The detail line from its parts, or nil for none. Joined with dots, each part kept whole,
    /// so a long line wraps between parts; stacked, at the accessibility sizes, a part to a line
    /// with no dots.
    public static func detailText(_ parts: [String], stacked: Bool) -> String? {
        guard !parts.isEmpty else { return nil }
        guard !stacked else { return parts.joined(separator: "\n") }
        // The space before a dot is no-break too, so a line never starts with one.
        return parts
            .map { $0.replacingOccurrences(of: " ", with: noBreakSpace) }
            .joined(separator: "\(noBreakSpace)· ")
    }
}

let noBreakSpace = "\u{00A0}"

/// Everything above a view's bottom edge, however far it reaches up or to either side: the cut
/// is the bottom edge alone.
private nonisolated struct BottomClip: Shape {
    func path(in rect: CGRect) -> Path {
        let far = max(rect.width, rect.height) * 4
        return Path(CGRect(
            x: rect.minX - far,
            y: rect.minY - far,
            width: rect.width + far * 2,
            height: rect.height + far,
        ))
    }
}

/// A row grown into the current exercise of a workout.
public struct RowFocus: Equatable {
    /// Which set it is on: "Set 1 of 3", and "done" after it while resting.
    public var place: SetPlace
    /// The side the set works, "Left", for an exercise done one side at a time.
    public var side: String?
    /// The exercise's own equipment, as capsules; none for an exercise that needs none.
    public var equipment: [String]
    public var figures: [Figure]
    /// The figures in words, for VoiceOver.
    public var spokenFigures: String
    /// What follows the set, at the caption line's end: "then rest 1:00", "last set"; nil for
    /// nothing.
    public var after: String?
    /// `after` in words, for VoiceOver, "then rest 1 minute": a clock time read as one.
    public var spokenAfter: String?
    /// Whether the side shows: not while resting after the set, when "done" takes its place;
    /// unseen, it keeps its room, so the caption line keeps the height a side gives it.
    public var showsSide: Bool {
        !place.isDone
    }

    /// Whether `after` shows; unseen, it keeps its room, as on a set's first side, where the
    /// other side follows, so the line holds the height the second side's rest gives it.
    public var showsAfter = true
    /// Words the line's end keeps room for, unseen, in every state of the set: a timed set's
    /// time and its "then rest", so the line, and the figures under it, never move between them.
    public var afterRoom: [String] = []
    public init(
        place: SetPlace,
        side: String? = nil,
        equipment: [String] = [],
        figures: [Figure],
        spokenFigures: String,
        after: String? = nil,
    ) {
        self.place = place
        self.after = after
        self.side = side
        self.equipment = equipment
        self.figures = figures
        self.spokenFigures = spokenFigures
    }

    /// A number shown large, with what it counts: "10" "reps".
    public struct Figure: Hashable {
        public var number: String
        public var unit: String

        public init(number: String, unit: String) {
            self.number = number
            self.unit = unit
        }
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        RowLabel(title: "Goblet squat", detail: "Kettlebell")
        RowLabel(
            title: "Dumbbell row",
            detail: ["3 × 10 reps per side", "50 lb"],
        )
        RowLabel(title: "Pigeon stretch", detail: ["60 s per side"])
        RowLabel(title: "Push-up", detail: nil)
        RowLabel(
            title: "Dumbbell row",
            detail: [],
            focus: RowFocus(
                place: SetPlace(word: "Set", number: 1, total: 3),
                equipment: ["Dumbbell", "Bench"],
                figures: [
                    .init(number: "10", unit: "reps per side"),
                    .init(number: "50", unit: "lb"),
                ],
                spokenFigures: "",
                after: "then rest 1:00",
            ),
            bars: SetProgress(done: 1, total: 3, spoken: ""),
        )
    }
    .padding()
    .background(Color.pp(.background))
}
