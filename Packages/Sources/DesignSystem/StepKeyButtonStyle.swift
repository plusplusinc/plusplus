import SwiftUI

/// A stepper's − or + key: a raised key the width it is given, its label the step it takes in
/// bold SF Mono, "−5" or "+15 s". `onPressChange` hears each press start and end, so a key can
/// repeat while held.
public struct StepKeyButtonStyle: ButtonStyle {
    private let onPressChange: (Bool) -> Void

    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 52
    @Environment(\.isEnabled) private var isEnabled
    @ObserveHotReload private var hotReload

    public init(onPressChange: @escaping (Bool) -> Void = { _ in }) {
        self.onPressChange = onPressChange
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ppStepKey)
            .foregroundStyle(.pp(.textPrimary))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .raisedKey(
                fill: .pp(.background),
                outlined: true,
                isPressed: configuration.isPressed && isEnabled,
                isEnabled: isEnabled,
            )
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPressChange(isPressed)
            }
            .hotReloadable()
    }
}

extension ButtonStyle where Self == StepKeyButtonStyle {
    /// `.buttonStyle(.stepKey)`.
    public static var stepKey: StepKeyButtonStyle {
        StepKeyButtonStyle()
    }
}

#Preview {
    HStack(spacing: Spacing.sm) {
        Button("\u{2212}5") { }
            .disabled(true)
        Button("+5") { }
    }
    .buttonStyle(.stepKey)
    .padding()
    .background(Color.pp(.surface))
}
