import SwiftUI

/// One cell of a stepper's joined − | + pair: its glyph in the secondary color on a 44 by 36 cell,
/// the touch carried to 44 tall, the cell darkening while pressed, the glyph dimmed when it can't
/// step. `onPressChange` hears each press start and end, so a key can repeat while held.
public struct StepKeyButtonStyle: ButtonStyle {
    private let onPressChange: (Bool) -> Void

    @ScaledMetric(relativeTo: .caption) private var width: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 36
    /// Past this, a cell would crowd the number beside it at the largest sizes.
    private static let largest = CGSize(width: 72, height: 60)
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
            .frame(width: min(width, Self.largest.width), height: min(height, Self.largest.height))
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
        .padding()
        .background(Color.pp(.surface))
}
