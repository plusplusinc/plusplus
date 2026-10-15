import SwiftUI

/// A value with − and + keys around it, under its name and a note on what the number means:
/// "Reps" over "Per side", "Weight" over "Bar, total". The name leads at the default sizes; at
/// the accessibility sizes it sits above, and the keys take the full width either side of the
/// value.
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
            value: { Text(verbatim: "3").ppValueFont() },
        )
        StepperRow(
            title: "Weight",
            note: "One dumbbell",
            spokenValue: "Not set",
            canDecrease: false,
            canIncrease: true,
            onDecrease: { },
            onIncrease: { },
            value: { Text(verbatim: "Not set") },
        )
    }
    .padding()
    .background(Color.pp(.background))
}
