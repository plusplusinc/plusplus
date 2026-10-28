import SwiftUI

/// A row's name over an optional detail line, given in parts. With no parts there is no line at
/// all, not an empty one. VoiceOver reads it as one element, "name, detail", with the detail in
/// words when `spokenDetail` is given.
///
/// Given a `focus`, it is the current exercise of a workout: the name grows large, and the detail
/// gives way to which set it is on, the exercise's equipment, and the plan's numbers, large, in
/// a label as tall as its `standing` leaves it. Changed in an animation, the name's size runs
/// between the two, and the numbers grow out of where the detail was.
public struct RowLabel: View {
    private let title: String
    private let detail: [String]
    private let spokenDetail: String?
    private let focus: RowFocus?
    private let standing: RowStanding?
    /// Logs the current exercise's set, given with `focus`: the slide under its numbers.
    private let onLog: (() -> Void)?

    /// The current exercise's numbers: 104pt at the default size.
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 104

    /// The label's height as a row, which the standing height runs from and back to, so the
    /// label grows and shrinks over the whole animation, on its curve.
    @State private var restingHeight: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObserveHotReload private var hotReload

    public init(
        title: String,
        detail: [String],
        spokenDetail: String? = nil,
        focus: RowFocus? = nil,
        standing: RowStanding? = nil,
        onLog: (() -> Void)? = nil,
    ) {
        self.title = title
        self.detail = detail
        self.spokenDetail = spokenDetail
        self.focus = focus
        self.standing = standing
        self.onLog = onLog
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
            standing: standing?.height,
        ) {
            column(detailText)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    if focus == nil {
                        restingHeight = height
                    }
                }
            if let next = standing?.next {
                Self(title: next.title, detail: next.detail).railRowStand()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func column(_ detailText: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .modifier(TitleFont(growth: focus == nil ? 0 : 1))
                .foregroundStyle(.pp(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
            // Out of a workout, a row with no detail has nothing under its name, not even
            // spacing.
            if detailText != nil || focus != nil {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // The detail line gives way to which set it is on, in the same place.
                    ZStack(alignment: .topLeading) {
                        if let detailText {
                            Text(AttributedString.monoNumbers(
                                detailText,
                                font: .ppRowDetailNumber,
                            ))
                            .font(.ppRowDetail)
                            .foregroundStyle(.pp(.textSecondary))
                            .opacity(focus == nil ? 1 : 0)
                        }
                        if let focus {
                            progressLine(focus)
                                .transition(.opacity)
                        }
                    }
                    if let focus, !focus.equipment.isEmpty {
                        Capsules(focus.equipment)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity
                                        .animation(.snappy(duration: 0.3).delay(0.15)),
                                    removal: .opacity.animation(.snappy(duration: 0.15)),
                                ),
                            )
                    }
                    if let focus, let onLog {
                        // Below the numbers, which give way first.
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            figures(focus)
                            SlideToLog(onLog: onLog)
                                .layoutPriority(1)
                        }
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.3, anchor: .topLeading)
                                    .combined(with: .opacity)
                                    .animation(.snappy(duration: 0.35).delay(0.2)),
                                removal: .opacity.animation(.snappy(duration: 0.15)),
                            ),
                        )
                    } else if let focus {
                        // In once the rows below have mostly stepped aside, so the numbers
                        // don't grow over them.
                        figures(focus)
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.3, anchor: .topLeading)
                                        .combined(with: .opacity)
                                        .animation(.snappy(duration: 0.35).delay(0.2)),
                                    removal: .opacity.animation(.snappy(duration: 0.15)),
                                ),
                            )
                    }
                }
            }
        }
    }

    /// Which set it is on, "Set 1 of 3", and the side, "· Left", set off in the name's color.
    /// A new set rolls in from below as the old one rolls out above.
    private func progressLine(_ focus: RowFocus) -> some View {
        var line = AttributedString(focus.progress)
        if let side = focus.side {
            line += AttributedString("\(noBreakSpace)·\(noBreakSpace)")
            var sideText = AttributedString(side)
            sideText.foregroundColor = .pp(.textPrimary)
            line += sideText
        }
        // Clipped around the line, so the rolls show only within it.
        return ZStack(alignment: .topLeading) {
            Text(line)
                .font(.ppCurrentProgress)
                .foregroundStyle(.pp(.textSecondary))
                // Whole, wrapped as far as it needs: only the numbers give way.
                .fixedSize(horizontal: false, vertical: true)
                .id(line)
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
            [title, [focus.progress, focus.side].compactMap(\.self).joined(separator: ", "),
             focus.spokenFigures]
        } else {
            [title, spokenDetail ?? detail.joined(separator: ", ")]
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
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

/// The name's font: `ppRowTitle` on a row, `ppCurrentTitle` on the current exercise, and,
/// as `growth` animates between 0 and 1, a semibold system font at every size between, so the
/// name grows smoothly: Text's own interpolation between the two fonts jumped. At either end it
/// is the token itself, so a row reads exactly as one out of a workout at every text size.
private struct TitleFont: ViewModifier, Animatable {
    var growth: CGFloat

    nonisolated var animatableData: CGFloat {
        get { growth }
        set { growth = newValue }
    }

    @Environment(\.fontResolutionContext) private var fontContext
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        content
            .font(font)
            .hotReloadable()
    }

    private var font: Font {
        switch growth {
        case ...0: .ppRowTitle
        case 1...: .ppCurrentTitle
        default:
            .system(
                size: size(of: .ppRowTitle) * (1 - growth) + size(of: .ppCurrentTitle) * growth,
                weight: .semibold,
            )
        }
    }

    private func size(of font: Font) -> CGFloat {
        font.resolve(in: fontContext).pointSize
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
            standing: RowStanding(height: 300),
        )
    }
    .padding()
    .background(Color.pp(.background))
}
