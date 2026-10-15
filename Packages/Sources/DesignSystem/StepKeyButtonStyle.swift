import SwiftUI

/// A stepper's − or + key: a small key-shaped button, its icon growing with the text, dimmed
/// when it can't step.
public struct StepKeyButtonStyle: ButtonStyle {
    @ScaledMetric(relativeTo: .body) private var minWidth: CGFloat = 50
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 48
    @Environment(\.isEnabled) private var isEnabled
    @ObserveHotReload private var hotReload

    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.key)
        configuration.label
            .labelStyle(.iconOnly)
            .font(.ppButton)
            .foregroundStyle(.pp(.textPrimary))
            .frame(minWidth: minWidth, minHeight: minHeight)
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
