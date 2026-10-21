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

    /// The name's size on a row, as `ppRowTitle`, and grown on the current exercise. Sizes, not
    /// two fonts, so the name grows through every size between: Text's own interpolation
    /// between the two fonts jumped.
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .title) private var currentTitleSize: CGFloat = 28
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
        return StandingHeight(height: height, endHeight: height) {
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
                .modifier(SemiboldSize(size: focus == nil ? titleSize : currentTitleSize))
                .foregroundStyle(.pp(.textPrimary))
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
                    Text(focus?.progress ?? "")
                        .font(.ppCurrentProgress)
                        .foregroundStyle(.pp(.textSecondary))
                        .opacity(focus == nil ? 0 : 1)
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

    /// Each number large, with what it counts beside it.
    private func figures(_ focus: RowFocus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(focus.figures, id: \.self) { figure in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(figure.number)
                        .font(.system(size: figureSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(.pp(.textPrimary))
                        .minimumScaleFactor(0.5)
                    Text(figure.unit)
                        .font(.ppCurrentUnit)
                        .foregroundStyle(.pp(.textSecondary))
                }
                .lineLimit(1)
            }
        }
        .fixedSize()
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
/// and taller by however far the subview runs past `endHeight`, the height it animates to. The
/// subview takes its new height at once, its new parts fading in later: counted whole, it held the
/// label at that height until the animated one passed it, so the rows below started late. A
/// frame's `minHeight` animated from 0 laid the row out at no height for the first frame.
private struct StandingHeight: Layout {
    var height: CGFloat
    /// Not animated: where `height` is going.
    let endHeight: CGFloat

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(ProposedViewSize(
            width: proposal.width,
            height: nil,
        )) ?? .zero
        // The content takes its new height at once, so it counts only past the end height.
        return CGSize(width: size.width, height: height + max(size.height - endHeight, 0))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        // At its own height: offered the standing height, it would center in it.
        let proposal = ProposedViewSize(width: bounds.width, height: nil)
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
    }
}

/// A semibold system font at a size that animates, so text grows through every size between.
private struct SemiboldSize: ViewModifier, Animatable {
    var size: CGFloat

    nonisolated var animatableData: CGFloat {
        get { size }
        set { size = newValue }
    }

    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .semibold))
            .hotReloadable()
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
