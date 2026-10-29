import SwiftUI

/// A row's name over an optional detail line, given in parts. With no parts there is no line at
/// all, not an empty one. VoiceOver reads it as one element, "name, detail", with the detail in
/// words when `spokenDetail` is given.
///
/// Given a `focus`, it is the current exercise of a workout: the name grows large, and the detail
/// gives way to which set it is on, the exercise's equipment, the plan's numbers, large, and the
/// slide that logs the set, the label growing to their height. Changed in an animation, the name
/// scales between its two sizes (`GrowingName`), and the parts under it come in, and go, in turn
/// (`SetMotion`).
public struct RowLabel: View {
    private let title: String
    private let detail: [String]
    private let spokenDetail: String?
    private let focus: RowFocus?
    /// Logs the current exercise's set, given with `focus`: the slide under its numbers.
    private let log: LogStep?
    /// How far the exercise is through its sets in a workout, shown as bars at the trailing
    /// end of its detail line, or of its progress line on the current exercise.
    private let bars: SetProgress?
    /// Whether the name stands at the current exercise's size: with `focus`, and on the row a
    /// workout is moving to, ahead of its other parts.
    private let isNameGrown: Bool
    /// Whether the parts under the name are going, ahead of the row closing.
    private let isLeaving: Bool

    /// The current exercise's numbers: 104pt at the default size.
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 104

    /// The label's height as a row, which its height runs from and back to, so the
    /// label grows and shrinks over the whole animation, on its curve.
    @State private var restingHeight: CGFloat = 0
    /// The label's height as the current exercise, which the height runs from as it shrinks back:
    /// by then its column has given up the parts that made it that tall.
    @State private var grownHeight: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObserveHotReload private var hotReload

    public init(
        title: String,
        detail: [String],
        spokenDetail: String? = nil,
        focus: RowFocus? = nil,
        bars: SetProgress? = nil,
        log: LogStep? = nil,
        isNameGrown: Bool? = nil,
        isLeaving: Bool = false,
    ) {
        self.title = title
        self.detail = detail
        self.spokenDetail = spokenDetail
        self.focus = focus
        self.log = log
        self.bars = bars
        self.isNameGrown = isNameGrown ?? (focus != nil)
        self.isLeaving = isLeaving
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
            .hotReloadable()
    }

    /// The name stays where it is as the row grows: the label stands at its height from the start,
    /// from its top, and the equipment and the numbers come in below the name inside it.
    private func content(_ detailText: String?) -> some View {
        StandingHeight(
            growth: focus == nil ? 0 : 1,
            isCurrent: focus != nil,
            restingHeight: restingHeight,
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
        // shows only once the rows below have made room for it, never over them.
        .clipShape(BottomClip(isOn: focus != nil))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func column(_ detailText: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            GrowingName(title: title, growth: isNameGrown ? 1 : 0)
            // Out of a workout, a row with no detail has nothing under its name, not even
            // spacing.
            if detailText != nil || focus != nil {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // The detail line gives way to which set it is on, in the same place, the
                    // bars at its trailing end.
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        lines(detailText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let bars {
                            // Kept as the row leaves: on a superset's member, the round goes on.
                            barsOnFirstLine(bars)
                                .part(.progress, isLeaving: false)
                        }
                    }
                    if let focus, !focus.equipment.isEmpty {
                        Capsules(focus.equipment)
                            .part(.equipment, isLeaving: isLeaving)
                    }
                    if let focus {
                        figures(focus)
                            .part(.figures, isLeaving: isLeaving)
                    }
                    if focus != nil, let log {
                        SlideToLog(log.label, weight: log.weight, onLog: log.action)
                            .layoutPriority(1)
                            .part(.slide, isLeaving: isLeaving)
                    }
                }
            }
        }
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
                .foregroundStyle(.pp(.textSecondary))
                // Never over the progress line: back once it has gone, and gone as the name
                // starts to grow, before the progress line comes in.
                .opacity(showsDetail ? 1 : 0)
                .animation(showsDetail ? SetMotion.detailIn : SetMotion.detailOut, value: showsDetail)
            }
            if let focus {
                progressLine(focus)
                    .part(.progress, isLeaving: isLeaving)
            }
        }
    }

    /// Whether the detail line shows: on a row at rest, its name at a row's size.
    private var showsDetail: Bool {
        focus == nil && !isNameGrown
    }

    /// The bars, centered on the first line of the line beside them: in a box as tall as one line
    /// of its text at every size.
    private func barsOnFirstLine(_ bars: SetProgress) -> some View {
        ZStack {
            Text(verbatim: "0")
                .font(focus == nil ? .ppRowDetail : .ppCurrentProgress)
                .hidden()
            SetBars(bars, isCurrent: focus != nil)
        }
        .fixedSize()
    }

    /// Which set it is on, "Set 1 of 3", and the side, "· Left", set off in the name's color.
    /// Each part rolls on its own as it changes, the new one in from below as the old one goes
    /// out above, so a switch from Left to Right rolls only the side, and the next set rolls both.
    /// Side by side where they fit, else the side under the set (`FigureLayout`).
    @ViewBuilder
    private func progressLine(_ focus: RowFocus) -> some View {
        if let side = focus.side {
            FigureLayout(spacing: 0) {
                rolling(focus.progress, color: .textSecondary)
                rolling("\(noBreakSpace)·\(noBreakSpace)\(side)", color: .textPrimary, dot: true)
            }
        } else {
            rolling(focus.progress, color: .textSecondary)
        }
    }

    /// One part of the progress line, rolling as it changes, clipped around itself so the roll
    /// shows only within it. The dot before a side stays in the set's gray.
    private func rolling(_ text: String, color: ColorToken, dot: Bool = false) -> some View {
        var line = AttributedString(text)
        line.foregroundColor = .pp(color)
        if dot, let range = line.range(of: "\(noBreakSpace)·\(noBreakSpace)") {
            line[range].foregroundColor = .pp(.textSecondary)
        }
        return ZStack(alignment: .topLeading) {
            Text(line)
                .font(.ppCurrentProgress)
                .fixedSize(horizontal: false, vertical: true)
                .id(text)
                .transition(.push(from: .bottom))
        }
        .clipped()
    }

    /// Each number large, with what it counts beside it, or, where the two don't fit side by
    /// side, as at the accessibility sizes, under it, the number shrinking to fit the width.
    private func figures(_ focus: RowFocus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(focus.figures, id: \.self) { figure in
                FigureLayout(spacing: Spacing.sm) {
                    number(figure)
                    unit(figure)
                }
            }
        }
    }

    private func number(_ figure: RowFocus.Figure) -> some View {
        Text(figure.number)
            .font(.system(size: figureSize, weight: .bold, design: .monospaced))
            .foregroundStyle(.pp(.textPrimary))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
    }

    private func unit(_ figure: RowFocus.Figure) -> some View {
        Text(figure.unit)
            .font(.ppCurrentUnit)
            .foregroundStyle(.pp(.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var spokenLabel: String {
        let parts = if let focus {
            [
                title,
                [focus.progress, focus.side].compactMap(\.self).joined(separator: ", "),
                focus.spokenFigures,
            ]
        } else {
            [title, spokenDetail ?? detail.joined(separator: ", ")]
        }
        return (parts + [bars?.spoken ?? ""]).filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The detail line from its parts, or nil for none. Joined with dots, each part kept whole,
    /// so a long line wraps between parts; stacked, at the accessibility sizes, a part to a line
    /// with no dots.
    static func detailText(_ parts: [String], stacked: Bool) -> String? {
        guard !parts.isEmpty else { return nil }
        guard !stacked else { return parts.joined(separator: "\n") }
        // The space before a dot is no-break too, so a line never starts with one.
        return parts
            .map { $0.replacingOccurrences(of: " ", with: noBreakSpace) }
            .joined(separator: "\(noBreakSpace)· ")
    }
}

private let noBreakSpace = "\u{00A0}"

/// Everything above a view's bottom edge, however far it reaches up or to either side: the cut
/// is the bottom edge alone, and only while `isOn`.
private nonisolated struct BottomClip: Shape {
    let isOn: Bool

    func path(in rect: CGRect) -> Path {
        let far = max(rect.width, rect.height) * 4
        return Path(CGRect(
            x: rect.minX - far,
            y: rect.minY - far,
            width: rect.width + far * 2,
            height: rect.height + far * (isOn ? 1 : 2),
        ))
    }
}

extension View {
    /// One of the current exercise's parts under its name, coming in and going in turn
    /// (`SetMotion`): in, fading as it rises into place once the row has room; going, while
    /// `isLeaving`, fading as it drops, before the row closes. Taken out any other way, as a
    /// workout ends, it fades.
    func part(_ part: SetMotion.Part, isLeaving: Bool) -> some View {
        opacity(isLeaving ? 0 : 1)
            .offset(y: isLeaving ? SetMotion.leaveDrop : 0)
            .animation(
                isLeaving
                    ? .easeIn(duration: SetMotion.leaveFade).delay(SetMotion.leaveDelay(part))
                    : nil,
                value: isLeaving,
            )
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: SetMotion.arriveRise))
                        .animation(
                            .easeOut(duration: SetMotion.arriveFade)
                                .delay(SetMotion.arriveDelay(part)),
                        ),
                    removal: .opacity.animation(.easeOut(duration: SetMotion.leaveFade)),
                ),
            )
    }
}

/// The slide that logs the current exercise's set: what it says, how firm its haptic is, and
/// what it does.
public struct LogStep {
    public var label: String
    public var weight: SlideToLog.Weight
    public var action: () -> Void

    public init(label: String, weight: SlideToLog.Weight = .set, action: @escaping () -> Void) {
        self.label = label
        self.weight = weight
        self.action = action
    }
}

/// A row grown into the current exercise of a workout.
public struct RowFocus: Equatable {
    /// Which set it is on: "Set 1 of 3".
    public var progress: String
    /// The side the set works, "Left", for an exercise done one side at a time.
    public var side: String?
    /// The exercise's own equipment, as capsules; none for an exercise that needs none.
    public var equipment: [String]
    public var figures: [Figure]
    /// The figures in words, for VoiceOver.
    public var spokenFigures: String
    public init(
        progress: String,
        side: String? = nil,
        equipment: [String] = [],
        figures: [Figure],
        spokenFigures: String,
    ) {
        self.progress = progress
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
                progress: "Set 1 of 3",
                equipment: ["Dumbbell", "Bench"],
                figures: [
                    .init(number: "10", unit: "reps per side"),
                    .init(number: "50", unit: "lb"),
                ],
                spokenFigures: "",
            ),
        )
    }
    .padding()
    .background(Color.pp(.background))
}
