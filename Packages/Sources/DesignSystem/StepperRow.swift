import SwiftUI

/// A compact row for a value: its name leading, with a note on what the number means under it
/// ("Reps" over "Per side", "Weight" over "Bar, total"), and trailing, the value in a small box
/// and a joined − | + pair whose keys repeat while held. At the accessibility sizes the name sits
/// above, and the value and the pair below it. Rows go on a card, `ppCard()`, a divider between
/// them.
///
/// VoiceOver reads the row as one adjustable element, "Reps, Per side", with the value in words:
/// swiping up or down steps it, so the keys themselves are hidden from it, and its "Type a value"
/// action starts typing. While its number is being typed, the row exposes what it holds, so
/// VoiceOver reaches the field.
public struct StepperRow<Value: View>: View {
    private let title: String
    private let note: String?
    private let spokenValue: String
    private let canDecrease: Bool
    private let canIncrease: Bool
    private let onDecrease: () -> Void
    private let onIncrease: () -> Void
    private let isTyping: Bool
    private let onType: () -> Void
    private let value: Value

    @ScaledMetric(relativeTo: .footnote) private var minHeight: CGFloat = 52
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObserveHotReload private var hotReload

    public init(
        title: String,
        note: String?,
        spokenValue: String,
        canDecrease: Bool,
        canIncrease: Bool,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void,
        isTyping: Bool = false,
        onType: @escaping () -> Void = { },
        @ViewBuilder value: () -> Value,
    ) {
        self.title = title
        self.note = note
        self.spokenValue = spokenValue
        self.canDecrease = canDecrease
        self.canIncrease = canIncrease
        self.onDecrease = onDecrease
        self.onIncrease = onIncrease
        self.isTyping = isTyping
        self.onType = onType
        self.value = value()
    }

    public var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    label
                    HStack(spacing: Spacing.sm) {
                        value
                        Spacer(minLength: 0)
                        pair
                    }
                }
                .padding(.vertical, Spacing.sm)
            } else {
                HStack(spacing: Spacing.sm) {
                    label
                    Spacer(minLength: 0)
                    value
                    pair
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .accessibilityElement(children: isTyping ? .contain : .ignore)
        .accessibilityLabel([title, note].compactMap(\.self).joined(separator: ", "))
        .accessibilityValue(spokenValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canIncrease {
                    onIncrease()
                }
            case .decrement: if canDecrease {
                    onDecrease()
                }
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Type a value", onType)
        .hotReloadable()
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(.ppStepperLabel)
                .foregroundStyle(.pp(.textSecondary))
            if let note {
                Text(note)
                    .font(.ppStepperNote)
                    .foregroundStyle(.pp(.textSecondary))
            }
        }
    }

    private var pair: some View {
        StepPair(
            canDecrease: canDecrease,
            canIncrease: canIncrease,
            onDecrease: onDecrease,
            onIncrease: onIncrease,
        )
    }
}

extension View {
    /// A card holding rows: surface fill, a hairline outline.
    public func ppCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card)
        return background(.pp(.surface), in: shape)
            .overlay(shape.strokeBorder(.pp(.borderStrong)))
    }
}

/// The line between two rows on a card.
public struct CardDivider: View {
    @ObserveHotReload private var hotReload

    public init() { }

    public var body: some View {
        Rectangle()
            .fill(.pp(.borderStrong))
            .frame(height: 1)
            .hotReloadable()
    }
}

#Preview {
    VStack(spacing: 0) {
        StepperRow(
            title: "Sets",
            note: nil,
            spokenValue: "3 sets",
            canDecrease: true,
            canIncrease: true,
            onDecrease: { },
            onIncrease: { },
            value: { NumberFieldContent(text: "3", unit: nil, isEditing: false, blinks: false) },
        )
        CardDivider()
        StepperRow(
            title: "Weight",
            note: "Bar, total",
            spokenValue: "Not set",
            canDecrease: false,
            canIncrease: true,
            onDecrease: { },
            onIncrease: { },
            value: { NumberFieldContent(text: nil, unit: nil, isEditing: false, blinks: false) },
        )
    }
    .ppCard()
    .padding()
    .background(Color.pp(.background))
}
