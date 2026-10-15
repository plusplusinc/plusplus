import SwiftUI

/// A value with − and + keys around it, under its name and a note on what the number means:
/// "Reps" over "Per side", "Weight" over "Bar, total". The name leads at the default sizes; at
/// the accessibility sizes it sits above, and the keys take the full width either side of the
/// value.
///
/// VoiceOver reads the row as one adjustable element, "Reps, Per side", with the value in words,
/// and swiping up or down steps it, so the keys themselves are hidden from it.
public struct StepperRow<Value: View>: View {
    private let title: String
    private let note: String?
    private let spokenValue: String
    private let canDecrease: Bool
    private let canIncrease: Bool
    private let onDecrease: () -> Void
    private let onIncrease: () -> Void
    private let value: Value

    @ScaledMetric(relativeTo: .title2) private var valueWidth: CGFloat = 126
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
        @ViewBuilder value: () -> Value,
    ) {
        self.title = title
        self.note = note
        self.spokenValue = spokenValue
        self.canDecrease = canDecrease
        self.canIncrease = canIncrease
        self.onDecrease = onDecrease
        self.onIncrease = onIncrease
        self.value = value()
    }

    public var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    label
                    HStack(spacing: Spacing.sm) {
                        decrease
                        value.frame(maxWidth: .infinity)
                        increase
                    }
                }
            } else {
                HStack(spacing: Spacing.sm) {
                    label.frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 0) {
                        decrease
                        value.frame(width: valueWidth)
                        increase
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, note].compactMap(\.self).joined(separator: ", "))
        .accessibilityValue(spokenValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canIncrease { onIncrease() }
            case .decrement: if canDecrease { onDecrease() }
            @unknown default: break
            }
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

    private var decrease: some View {
        Button("Decrease", systemImage: "minus", action: onDecrease)
            .buttonStyle(.stepKey)
            .disabled(!canDecrease)
    }

    private var increase: some View {
        Button("Increase", systemImage: "plus", action: onIncrease)
            .buttonStyle(.stepKey)
            .disabled(!canIncrease)
    }
}

/// A stepper's number with its unit drawn small after it, or "Not set" when it has none.
public struct StepperValue: View {
    private let number: String?
    private let unit: String?
    private let placeholder: String

    @ObserveHotReload private var hotReload

    public init(number: String?, unit: String?, placeholder: String = "Not set") {
        self.number = number
        self.unit = unit
        self.placeholder = placeholder
    }

    public var body: some View {
        Group {
            if let number {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(number)
                        .ppValueFont()
                        .foregroundStyle(.pp(.textPrimary))
                    if let unit {
                        Text(unit)
                            .font(.ppValueUnit)
                            .foregroundStyle(.pp(.textSecondary))
                    }
                }
            } else {
                Text(placeholder)
                    .font(.ppValuePlaceholder)
                    .foregroundStyle(.pp(.textSecondary))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .hotReloadable()
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        StepperRow(
            title: "Sets",
            note: nil,
            spokenValue: "3 sets",
            canDecrease: true,
            canIncrease: true,
            onDecrease: { },
            onIncrease: { },
        ) {
            StepperValue(number: "3", unit: nil)
        }
        StepperRow(
            title: "Weight",
            note: "One dumbbell",
            spokenValue: "Not set",
            canDecrease: false,
            canIncrease: true,
            onDecrease: { },
            onIncrease: { },
        ) {
            StepperValue(number: nil, unit: nil)
        }
    }
    .padding()
    .background(Color.pp(.background))
}
