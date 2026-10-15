import SwiftUI

/// A value to set, as a row: its name leading and its value trailing, the number large with the
/// words after it small ("10 per side", "15 lb each"), on a rounded fill that makes the two ends
/// one row. The whole row is a button that opens its wheel in the gap under it, on whatever is
/// behind, the fill brightening while it is open; a second tap closes it. The gap widens from the
/// row down, uncovering the wheel in place and pushing what's below, and narrows back up. A
/// changed number rolls its digits, up as `amount` rises and down as it falls,
/// or with Reduce Motion swaps at once. At the accessibility sizes the value sits under the name.
///
/// VoiceOver reads the row as one button, "Weight, 15 pounds each", with a hint that it expands
/// or collapses its picker; once open, the wheel is the system's own adjustable picker.
public struct ValueRow<Wheel: View>: View {
    private let title: String
    private let value: String
    private let suffix: String?
    private let amount: Double?
    private let spokenValue: String
    private let isOpen: Bool
    private let identifier: String
    private let onToggle: () -> Void
    private let wheel: Wheel

    /// The row's least height, the least a tap target takes.
    @ScaledMetric(relativeTo: .title2) private var minHeight: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    /// - Parameters:
    ///   - suffix: The words after the number, drawn small: its unit, and "per side" or "each".
    ///   - amount: What the value stands for, so a change rolls its digits up or down.
    ///   - identifier: The row's accessibility identifier, on the row and not its wheel.
    public init(
        title: String,
        value: String,
        suffix: String?,
        amount: Double?,
        spokenValue: String,
        isOpen: Bool,
        identifier: String,
        onToggle: @escaping () -> Void,
        @ViewBuilder wheel: () -> Wheel,
    ) {
        self.title = title
        self.value = value
        self.suffix = suffix
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
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            label
                            valueText
                        }
                    } else {
                        HStack(spacing: Spacing.sm) {
                            label
                            Spacer(minLength: Spacing.sm)
                            valueText
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                .background(
                    .pp(isOpen ? .borderStrong : .surface),
                    in: .rect(cornerRadius: Radius.card),
                )
                .contentShape(.rect(cornerRadius: Radius.card))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(spokenValue)
            .accessibilityHint(isOpen ? "Collapses the picker." : "Expands a picker.")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier)
            // Always laid out and rolled up to nothing while closed, rather than inserted: an
            // outgoing view kept its full size over the rows below until it was gone.
            // Clipped, so at every height on the way it draws nothing over the rows around it.
            RevealLayout(fraction: isOpen ? 1 : 0) { wheel }
                .clipped()
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)
        }
        .hotReloadable()
    }

    private var label: some View {
        Text(title)
            .font(.ppRowTitle)
            .foregroundStyle(.pp(.textPrimary))
    }

    private var valueText: some View {
        let rolls = !reduceMotion
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(verbatim: value)
                .font(.ppPlanValue)
                .foregroundStyle(.pp(.textPrimary))
                .contentTransition(rolls ? .numericText(value: amount ?? 0) : .identity)
                .animation(rolls ? .valueChange : nil, value: amount)
            if let suffix {
                Text(suffix)
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textSecondary))
            }
        }
        .lineLimit(1)
    }
}

/// Lays out its one view at full size from its top, and takes `fraction` of its height: a wheel
/// uncovered from its top edge down as it opens, what's below moving down in step, and, clipped,
/// drawing nothing past the height it has.
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
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil),
        )
    }
}

extension Animation {
    /// A value changing in place, such as a plan's number rolling to its next.
    public static let valueChange = Animation.snappy(duration: 0.1)
}

#Preview {
    @Previewable @State var open: String? = "Weight"
    @Previewable @State var weight = 25
    VStack(spacing: Spacing.xs) {
        ForEach(
            [("Sets", "3", nil), ("Reps", "10", "per side"), ("Weight", "\(weight)", "lb each")],
            id: \.0,
        ) { title, value, suffix in
            ValueRow(
                title: title,
                value: value,
                suffix: suffix,
                amount: Double(value),
                spokenValue: value,
                isOpen: open == title,
                identifier: title,
                onToggle: { withAnimation(.snappy) { open = open == title ? nil : title } },
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
    }
    .padding()
    .background(Color.pp(.background))
}
