import SwiftUI

/// A stepper's − or + key: a small key-shaped button, its icon growing with the text, dimmed
/// when it can't step. The key grows with the text only so far, leaving the number between two
/// keys room at the largest sizes.
public struct StepKeyButtonStyle: ButtonStyle {
    @ScaledMetric(relativeTo: .body) private var minWidth: CGFloat = 50
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 48
    /// About the board's key at AX5, and well over the 44pt touch target.
    private static let largest = CGSize(width: 88, height: 80)
    @Environment(\.isEnabled) private var isEnabled
    @ObserveHotReload private var hotReload

    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.key)
        configuration.label
            .labelStyle(.iconOnly)
            .font(.ppButton)
            .foregroundStyle(.pp(.textPrimary))
            .padding(Spacing.xs)
            .frame(
                minWidth: min(minWidth, Self.largest.width),
                minHeight: min(minHeight, Self.largest.height),
            )
            .background(shape.fill(.pp(.surface)))
            .overlay(shape.strokeBorder(.pp(.borderStrong)))
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
            .keyPressAnimation(isPressed: configuration.isPressed)
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
    HStack {
        Button("Decrease", systemImage: "minus") { }
            .disabled(true)
        Button("Increase", systemImage: "plus") { }
    }
    .buttonStyle(.stepKey)
    .padding()
    .background(Color.pp(.background))
}
