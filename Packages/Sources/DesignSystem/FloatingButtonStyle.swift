import SwiftUI

/// A round glass button floating over a screen's content, as ++ is in the bar: its label's icon
/// alone, in the primary text color, on a 56 pt circle of interactive glass, which answers a
/// press itself. The circle scales with the icon's text style, so at the accessibility sizes the
/// icon stays inside it. `primaryKeyBar(…floating:)` places one above the key.
public struct FloatingButtonStyle: ButtonStyle {
    @ScaledMetric(relativeTo: FloatingButton.textStyle) private var diameter = FloatingButton
        .diameter

    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.ppFloatingIcon)
            .foregroundStyle(.pp(.textPrimary))
            .frame(width: diameter, height: diameter)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

extension ButtonStyle where Self == FloatingButtonStyle {
    /// `.buttonStyle(.floating)`.
    public static var floating: FloatingButtonStyle {
        FloatingButtonStyle()
    }
}

/// The floating button's size, shared by the button and the room a list leaves for it.
enum FloatingButton {
    static let diameter: CGFloat = 56
    static let textStyle = Font.TextStyle.title2
}

/// Clear room as tall as a floating button, at the end of a list it floats over, so the last
/// row scrolls clear of it.
public struct FloatingButtonRoom: View {
    @ScaledMetric(relativeTo: FloatingButton.textStyle) private var height = FloatingButton.diameter

    public init() { }

    public var body: some View {
        Color.clear
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

#Preview {
    Button("Add exercise", systemImage: "plus") { }
        .buttonStyle(.floating)
        .padding()
        .background(Color.pp(.background))
}
