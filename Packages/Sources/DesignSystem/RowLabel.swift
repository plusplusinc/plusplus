import SwiftUI

/// A row's name over an optional detail line, given in parts. With no parts there is no line at
/// all, not an empty one. VoiceOver reads it as one element, "name, detail", with the detail in
/// words when `spokenDetail` is given.
///
/// Given a `focus`, it is the current exercise of a workout: the name grows large, and the detail
/// gives way to which set it is on, the exercise's equipment, and the plan's numbers, large, in
/// a label at least `minHeight` tall. Changed in an animation, the name's size runs between the
/// two, and the numbers grow out
/// of where the detail was.
public struct RowLabel: View {
    private let title: String
    private let detail: [String]
    private let spokenDetail: String?
    private let focus: RowFocus?

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
    ) {
        self.title = title
        self.detail = detail
        self.spokenDetail = spokenDetail
        self.focus = focus
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
        let height = focus?.minHeight ?? restingHeight
        return StandingHeight(height: height, endHeight: height, isResting: focus == nil) {
            column(detailText)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    if focus == nil {
                        restingHeight = height
                    }
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
                            Text(focus.progress)
                                .font(.ppCurrentProgress)
                                .foregroundStyle(.pp(.textSecondary))
                                // Whole, wrapped as far as it needs: only the numbers give way.
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        }
                    }
                    if let focus, !focus.equipment.isEmpty {
                        Capsules(focus.equipment)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.animation(.snappy(duration: 0.3).delay(0.15)),
                                    removal: .opacity.animation(.snappy(duration: 0.15)),
                                ),
                            )
                    }
                    if let focus {
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

    /// Each number large, with what it counts beside it, or, where the two don't fit side by
    /// side, as at the accessibility sizes, under it, the number shrinking to fit the width.
    private func figures(_ focus: RowFocus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(focus.figures, id: \.self) { figure in
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        number(figure)
                        unit(figure)
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        number(figure)
                        unit(figure)
                    }
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
            [title, focus.progress, focus.spokenFigures]
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

/// Its one subview, from its top, in a frame `height` tall, the height animating as a number,
/// and taller by however far the subview runs past both `height` and `endHeight`, the height it
/// animates to. The
/// subview takes its new height at once, its new parts fading in later: counted whole, it held the
/// label at that height until the animated one passed it, so the rows below started late. A
/// frame's `minHeight` animated from 0 laid the row out at no height for the first frame.
private struct StandingHeight: Layout {
    var height: CGFloat
    /// Not animated: where `height` is going.
    let endHeight: CGFloat
    /// Not animated: a row out of a workout, which, once any shrink has landed, is just as tall
    /// as its content: the height it last measured can be out of date.
    let isResting: Bool

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(offer(width: proposal.width)) ?? .zero
        if isResting, height == endHeight {
            return size
        }
        // The content takes its new height at once, so it counts only past the end height, and
        // past the standing height: shrinking, parts fading out still take their room, which
        // held the rows below until they had gone, then let them jump.
        let counted = max(size.height - max(endHeight, height), 0)
        return CGSize(width: size.width, height: height + counted)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: offer(width: bounds.width),
        )
    }

    /// What the subview is offered: as tall as it likes at rest, and on the current exercise
    /// the height it stands at, which its numbers shrink to fit at the largest text sizes, so the
    /// row after it stays in view. Placed from its top, at its own height: placed in the
    /// standing height, it would center in it.
    private func offer(width: CGFloat?) -> ProposedViewSize {
        ProposedViewSize(width: width, height: isResting ? nil : endHeight)
    }
}

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
            .system(size: size(of: .ppRowTitle) * (1 - growth) + size(of: .ppCurrentTitle) * growth,
                    weight: .semibold)
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
    /// The exercise's own equipment, as capsules; none for an exercise that needs none.
    public var equipment: [String]
    public var figures: [Figure]
    /// The figures in words, for VoiceOver.
    public var spokenFigures: String
    /// How tall the whole label stands, name included, so the row fills the screen but for the
    /// row after it.
    public var minHeight: CGFloat

    public init(
        progress: String,
        equipment: [String] = [],
        figures: [Figure],
        spokenFigures: String,
        minHeight: CGFloat,
    ) {
        self.progress = progress
        self.equipment = equipment
        self.figures = figures
        self.spokenFigures = spokenFigures
        self.minHeight = minHeight
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
                minHeight: 300,
            ),
        )
    }
    .padding()
    .background(Color.pp(.background))
}
