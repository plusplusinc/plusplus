import SwiftUI

/// A value to set, as a row: its name leading and its value trailing, the number large with the
/// words after it small ("10 per side", "15 lb each"), on a rounded fill that makes the two ends
/// one row. The whole row is a button; the selected row's fill is brighter. A changed number
/// rolls its digits, up as `amount` rises and down as it falls, or with Reduce Motion swaps at
/// once. At the accessibility sizes the value sits under the name.
///
/// VoiceOver reads the row as one button, "Weight, 15 pounds each", selected when it is.
public struct ValueRow: View {
    private let title: String
    private let value: String
    private let suffix: String?
    private let amount: Double?
    private let spokenValue: String
    private let isSelected: Bool
    private let identifier: String
    private let action: () -> Void

    @ScaledMetric(relativeTo: .title) private var minHeight: CGFloat = 60
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    /// - Parameters:
    ///   - suffix: The words after the number, drawn small: its unit, and "per side" or "each".
    ///   - amount: What the value stands for, so a change rolls its digits up or down.
    ///   - identifier: The row's accessibility identifier.
    public init(
        title: String,
        value: String,
        suffix: String?,
        amount: Double?,
        spokenValue: String,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void,
    ) {
        self.title = title
        self.value = value
        self.suffix = suffix
        self.amount = amount
        self.spokenValue = spokenValue
        self.isSelected = isSelected
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
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
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(
                .pp(isSelected ? .borderStrong : .surface),
                in: .rect(cornerRadius: Radius.card),
            )
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spokenValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
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

extension Animation {
    /// A value changing in place, such as a plan's number rolling to its next.
    public static let valueChange = Animation.snappy(duration: 0.1)
}

#Preview {
    @Previewable @State var selected = "Weight"
    VStack(spacing: Spacing.xs) {
        ForEach(
            [("Sets", "3", nil), ("Reps", "10", "per side"), ("Weight", "15", "lb each")],
            id: \.0,
        ) { title, value, suffix in
            ValueRow(
                title: title,
                value: value,
                suffix: suffix,
                amount: Double(value),
                spokenValue: value,
                isSelected: selected == title,
                identifier: title,
                action: { selected = title },
            )
        }
    }
    .padding()
    .background(Color.pp(.background))
}
