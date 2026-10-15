import SwiftUI

/// A value in a row, in a rail row's type: its name leading, with a note on what the number means
/// under it ("Reps" over "Per side", "Weight" over "Bar, total"), and the value trailing in a
/// filled capsule, its unit faint after it. A tap raises the row's wheel under it from the wheel's
/// bottom edge, and a second tap lowers it away; the capsule brightens while its
/// wheel is open. A changed
/// number rolls its digits, up as `amount` rises and down as it falls, or with Reduce Motion
/// swaps at once. At the accessibility sizes the capsule sits under the name.
///
/// VoiceOver reads the row as one button, "Weight, Pair, each", with the value in words; the
/// wheel, once open, is the system's own adjustable picker.
public struct PickerRow<Wheel: View>: View {
    private let title: String
    private let note: String?
    private let value: String
    private let unit: String?
    private let amount: Double?
    private let spokenValue: String
    private let isOpen: Bool
    private let identifier: String
    private let onToggle: () -> Void
    private let wheel: Wheel

    @ScaledMetric(relativeTo: .body) private var capsuleHeight: CGFloat = 36
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    /// - Parameters:
    ///   - amount: What the value stands for, so a change rolls its digits up or down.
    ///   - identifier: The row's accessibility identifier, on the row and not its wheel.
    public init(
        title: String,
        note: String?,
        value: String,
        unit: String?,
        amount: Double?,
        spokenValue: String,
        isOpen: Bool,
        identifier: String,
        onToggle: @escaping () -> Void,
        @ViewBuilder wheel: () -> Wheel,
    ) {
        self.title = title
        self.note = note
        self.value = value
        self.unit = unit
        self.amount = amount
        self.spokenValue = spokenValue
        self.isOpen = isOpen
        self.identifier = identifier
        self.onToggle = onToggle
        self.wheel = wheel()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            label
                            capsule
                        }
                    } else {
                        HStack(spacing: Spacing.sm) {
                            label
                            Spacer(minLength: Spacing.sm)
                            capsule
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([title, note].compactMap(\.self).joined(separator: ", "))
            .accessibilityValue(spokenValue)
            .accessibilityHint(isOpen ? "Collapses the picker." : "Expands a picker.")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier)
            // Always laid out and rolled up to nothing while closed, rather than inserted: an
            // outgoing view kept its full size over the rows below until it was gone.
            RevealLayout(fraction: isOpen ? 1 : 0) { wheel }
                .clipShape(TopAndBottom())
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)
        }
        .hotReloadable()
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(.ppRowTitle)
                .foregroundStyle(.pp(.textPrimary))
            if let note {
                Text(note)
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textSecondary))
            }
        }
    }

    private var capsule: some View {
        let rolls = !reduceMotion
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(verbatim: value)
                .font(.ppPlanValue)
                .foregroundStyle(.pp(.textPrimary))
                .contentTransition(rolls ? .numericText(value: amount ?? 0) : .identity)
                .animation(rolls ? .valueChange : nil, value: amount)
            if let unit {
                Text(unit)
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textSecondary))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, Spacing.md)
        .frame(minWidth: capsuleHeight, minHeight: capsuleHeight)
        .background(.pp(isOpen ? .borderStrong : .surface), in: .capsule)
    }
}

/// Clips what it shapes above and below its bounds only, so a background running past its sides,
/// such as an open wheel's edge to edge of the sheet, still reaches them.
private nonisolated struct TopAndBottom: Shape {
    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: -rect.width, dy: 0))
    }
}

/// Lays out its one view at full size from its bottom, and takes `fraction` of its height: a
/// wheel rising from its bottom edge as it opens, so in a sheet laid out from its bottom what's
/// above moves up in step and what's below stays put, and, clipped, drawing nothing past the
/// height it has.
private struct RevealLayout: Layout {
    var fraction: CGFloat

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let size = view.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: size.width, height: size.height * fraction)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        subviews.first?.place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY),
            anchor: .bottomLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil),
        )
    }
}

extension Animation {
    /// A value changing in place, such as a plan's number rolling to its next.
    public static let valueChange = Animation.snappy(duration: 0.1)
}

#Preview {
    @Previewable @State var isOpen = true
    @Previewable @State var weight = 25
    VStack(spacing: Spacing.md) {
        PickerRow(
            title: "Sets",
            note: nil,
            value: "3",
            unit: nil,
            amount: 3,
            spokenValue: "3 sets",
            isOpen: false,
            identifier: "sets",
            onToggle: { },
            wheel: { EmptyView() },
        )
        PickerRow(
            title: "Weight",
            note: "Pair, each",
            value: "\(weight)",
            unit: "lb",
            amount: Double(weight),
            spokenValue: "\(weight) pounds",
            isOpen: isOpen,
            identifier: "weight",
            onToggle: { isOpen.toggle() },
            wheel: {
                Picker("Weight", selection: $weight) {
                    ForEach(Array(stride(from: 5, through: 150, by: 5)), id: \.self) {
                        Text(verbatim: "\($0)").tag($0)
                    }
                }
                #if os(iOS)
                .pickerStyle(.wheel)
                #endif
            },
        )
    }
    .padding()
    .background(Color.pp(.background))
}
