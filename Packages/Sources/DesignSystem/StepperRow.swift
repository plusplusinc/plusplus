import SwiftUI

/// A value on a card: its name, and a note on what the number means under it ("Reps" over "Per
/// side", "Weight" over "Bar, total"), then the value, then a − and a + key side by side, each
/// labeled with the step it takes and repeating while held.
///
/// VoiceOver reads the row as one adjustable element, "Reps, Per side", with the value in words:
/// swiping up or down steps it, so the keys themselves are hidden from it, and its "Type a value"
/// action starts typing. While its number is being typed, the row exposes what it holds, so
/// VoiceOver reaches the field.
public struct StepperRow<Value: View>: View {
    private let title: String
    private let note: String?
    private let spokenValue: String
    private let decreaseLabel: String
    private let increaseLabel: String
    private let canDecrease: Bool
    private let canIncrease: Bool
    private let onDecrease: () -> Void
    private let onIncrease: () -> Void
    private let isTyping: Bool
    private let onType: () -> Void
    private let value: Value

    @ObserveHotReload private var hotReload

    public init(
        title: String,
        note: String?,
        spokenValue: String,
        decreaseLabel: String,
        increaseLabel: String,
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
        self.decreaseLabel = decreaseLabel
        self.increaseLabel = increaseLabel
        self.canDecrease = canDecrease
        self.canIncrease = canIncrease
        self.onDecrease = onDecrease
        self.onIncrease = onIncrease
        self.isTyping = isTyping
        self.onType = onType
        self.value = value()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            label
            value
            HStack(spacing: Spacing.sm) {
                StepKey(decreaseLabel, onStep: onDecrease)
                    .disabled(!canDecrease)
                StepKey(increaseLabel, onStep: onIncrease)
                    .disabled(!canIncrease)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.pp(.surface), in: RoundedRectangle(cornerRadius: Radius.card))
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
                .font(.ppRowTitle)
                .foregroundStyle(.pp(.textPrimary))
            if let note {
                Text(note)
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textSecondary))
            }
        }
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        StepperRow(
            title: "Sets",
            note: nil,
            spokenValue: "3 sets",
            decreaseLabel: "\u{2212}1",
            increaseLabel: "+1",
            canDecrease: true,
            canIncrease: true,
            onDecrease: { },
            onIncrease: { },
            value: { NumberFieldContent(text: "3", unit: nil, isEditing: false, blinks: false) },
        )
        StepperRow(
            title: "Weight",
            note: "One dumbbell",
            spokenValue: "Not set",
            decreaseLabel: "\u{2212}5",
            increaseLabel: "+5",
            canDecrease: false,
            canIncrease: true,
            onDecrease: { },
            onIncrease: { },
            value: { NumberFieldContent(text: nil, unit: nil, isEditing: false, blinks: false) },
        )
    }
    .padding()
    .background(Color.pp(.background))
}
