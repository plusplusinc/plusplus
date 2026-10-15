import SwiftUI

/// One cell of a stepper's joined − | + pair: its glyph as a key's content is drawn, on a cell 44
/// wide and as tall as its row's controls, the cell darkening while pressed, the glyph dimmed
/// when it can't step. `onPressChange` hears each press start and end, so a key can repeat while
/// held.
public struct StepKeyButtonStyle: ButtonStyle {
    private let onPressChange: (Bool) -> Void

    @ScaledMetric(relativeTo: .caption) private var width: CGFloat = 44
    /// Past this, a cell would crowd the number beside it at the largest sizes.
    private static let widest: CGFloat = 72
    @Environment(\.isEnabled) private var isEnabled
    @ObserveHotReload private var hotReload

    public init(onPressChange: @escaping (Bool) -> Void = { _ in }) {
        self.onPressChange = onPressChange
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.ppButton)
            .foregroundStyle(.pp(.textPrimary))
            .opacity(isEnabled ? 1 : 0.35)
            .frame(width: min(width, Self.widest))
            .frame(maxHeight: .infinity)
            .background(configuration.isPressed && isEnabled ? Color.pp(.background) : .clear)
            .contentShape(.rect)
            .keyPressAnimation(isPressed: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPressChange(isPressed)
            }
            .hotReloadable()
    }
}

#Preview {
    StepPair(canDecrease: false, canIncrease: true, onDecrease: { }, onIncrease: { })
        .frame(height: 44)
        .padding()
        .background(Color.pp(.surface))
}
