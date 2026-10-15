import SwiftUI

/// One cell of a stepper's joined − | + pair: its glyph in the secondary color on a cell 44 wide
/// and as tall as its row's controls, the touch reaching a little past it, the cell darkening
/// while pressed, the glyph dimmed when it can't step. `onPressChange` hears each press start and end, so a key can repeat while held.
public struct StepKeyButtonStyle: ButtonStyle {
    private let onPressChange: (Bool) -> Void

    @ScaledMetric(relativeTo: .caption) private var width: CGFloat = 44
    /// Past this, a cell would crowd the number beside it at the largest sizes.
    private static let widest: CGFloat = 72
    /// How far the touch reaches past the cell, taking a 36 tall cell to 44.
    private static let reach: CGFloat = 4
    @Environment(\.isEnabled) private var isEnabled
    @ObserveHotReload private var hotReload

    public init(onPressChange: @escaping (Bool) -> Void = { _ in }) {
        self.onPressChange = onPressChange
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.ppStepGlyph)
            .foregroundStyle(.pp(.textSecondary))
            .opacity(isEnabled ? 1 : 0.35)
            .frame(width: min(width, Self.widest))
            .frame(maxHeight: .infinity)
            .background(configuration.isPressed && isEnabled ? Color.pp(.background) : .clear)
            .contentShape(Rectangle().inset(by: -Self.reach))
            .keyPressAnimation(isPressed: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPressChange(isPressed)
            }
            .hotReloadable()
    }
}

#Preview {
    StepPair(canDecrease: false, canIncrease: true, onDecrease: { }, onIncrease: { })
        .frame(height: 36)
        .padding()
        .background(Color.pp(.surface))
}
