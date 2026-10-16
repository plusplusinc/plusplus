import SwiftUI

/// A value under its label on a rounded fill, the label leading and the value trailing, with
/// numbers in SF Mono. Tapping anywhere on it opens a − / + stepper inside it, under the value,
/// and tapping again closes it. VoiceOver reads it as one element, its value in words, and
/// steps it with a swipe up or down.
public struct ValueRow: View {
    private let label: String
    private let value: String
    private let spokenValue: String
    private let isOpen: Bool
    private let onToggle: () -> Void
    private let onStep: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObserveHotReload private var hotReload

    /// How a row opens and closes: the caller animates `isOpen` with it.
    public static let motion = Animation.snappy(duration: 0.25)
    /// The value's key and the stepper's keys sit this far inside their row on every side, so
    /// the row's corners are concentric with theirs.
    private static let inset = Spacing.sm
    private static let keyHeight: CGFloat = 60

    /// `onStep` gets 1 for a step up and -1 for a step down.
    public init(
        label: String,
        value: String,
        spokenValue: String,
        isOpen: Bool,
        onToggle: @escaping () -> Void,
        onStep: @escaping (Int) -> Void,
    ) {
        self.label = label
        self.value = value
        self.spokenValue = spokenValue
        self.isOpen = isOpen
        self.onToggle = onToggle
        self.onStep = onStep
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            region
        }
        .background(Color.pp(.surface), in: .rect(cornerRadius: Self.inset + Radius.key))
        .hotReloadable()
    }

    /// The whole row opens and closes its stepper. It's a tap, not a `Button`: a button's label
    /// trailed its row's fill by a quarter second as rows above it opened or closed.
    /// At the accessibility sizes the value goes under its label, so neither breaks mid-word.
    private var header: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout())
        return layout {
            Text(label)
                .font(.ppRowTitle)
                .foregroundStyle(.pp(.textPrimary))
                .padding(.top, stacked ? Spacing.sm : 0)
            if !stacked {
                Spacer()
            }
            Text(AttributedString.monoNumbers(value, font: .ppRowTitleNumber))
                .font(.ppRowTitle)
                .contentTransition(.numericText())
                .foregroundStyle(.pp(.textPrimary))
                .multilineTextAlignment(stacked ? .leading : .trailing)
                .padding(.horizontal, stacked ? 0 : Spacing.md - Spacing.xs)
                .padding(.vertical, Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Spacing.md)
        .padding([.vertical, .trailing], Self.inset)
        .contentShape(.rect)
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue)
        .accessibilityHint(isOpen ? "Closes its stepper." : "Opens a stepper.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onToggle() }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(by: 1)
            case .decrement: step(by: -1)
            @unknown default: break
            }
        }
    }

    /// The stepper under the value, always laid out: the region shows only as much of it as its
    /// height allows, so nothing draws past its edges, and the stepper, held to its top, fades
    /// in and out as it opens and closes.
    private var region: some View {
        HStack(spacing: Spacing.sm) {
            stepKey("Decrease", "minus", by: -1)
            stepKey("Increase", "plus", by: 1)
        }
        .padding([.horizontal, .bottom], Self.inset)
        .opacity(isOpen ? 1 : 0)
        .allowsHitTesting(isOpen)
        .accessibilityHidden(!isOpen)
        // Once for the pair of keys, so a step plays one tick.
        .sensoryFeedback(.selection, trigger: value)
        .frame(maxWidth: .infinity)
        .frame(height: isOpen ? nil : 0, alignment: .top)
        .clipped()
    }

    private func stepKey(_ title: String, _ image: String, by direction: Int) -> some View {
        Button {
            step(by: direction)
        } label: {
            // The whole key is the button, not just its glyph.
            Label(title, systemImage: image)
                .labelStyle(.iconOnly)
                .font(.ppButton)
                .foregroundStyle(.pp(.textPrimary))
                .frame(maxWidth: .infinity, minHeight: Self.keyHeight)
                .background(Color.pp(.background), in: .rect(cornerRadius: Radius.key))
                .contentShape(.rect(cornerRadius: Radius.key))
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
    }

    private func step(by direction: Int) {
        withAnimation(.snappy(duration: 0.15)) {
            onStep(direction)
        }
    }
}

#Preview {
    @Previewable @State var open = 1
    @Previewable @State var reps = 10
    VStack(spacing: Spacing.sm) {
        ValueRow(
            label: "Sets",
            value: "3",
            spokenValue: "3 sets",
            isOpen: open == 0,
            onToggle: { withAnimation(ValueRow.motion) { open = open == 0 ? -1 : 0 } },
            onStep: { _ in },
        )
        ValueRow(
            label: "Reps",
            value: "\(reps) per side",
            spokenValue: "\(reps) reps per side",
            isOpen: open == 1,
            onToggle: { withAnimation(ValueRow.motion) { open = open == 1 ? -1 : 1 } },
            onStep: { reps += $0 },
        )
        ValueRow(
            label: "Weight",
            value: "20 lb/side",
            spokenValue: "20 pounds per side",
            isOpen: open == 2,
            onToggle: { withAnimation(ValueRow.motion) { open = open == 2 ? -1 : 2 } },
            onStep: { _ in },
        )
    }
    .padding()
    .background(Color.pp(.background))
}
