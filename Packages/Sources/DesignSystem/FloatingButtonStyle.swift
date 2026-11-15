import SwiftUI

/// A round glass button floating over a screen's content, as ++ is in the bar: its label's icon
/// alone, in the primary text color, on a 56 pt circle of interactive glass, which answers a
/// press itself. The circle scales with the icon's text style up to the largest size short of the
/// accessibility sizes, as a bar's buttons stop there; past it, a long press shows the label in
/// the large content viewer. Scaled on, it grew past twice its size over the rows it floats on.
/// `primaryKeyBar(…floating:)` places one above the key.
public struct FloatingButtonStyle: ButtonStyle {
    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        FloatingCircle(label: configuration.label)
            .dynamicTypeSize(...FloatingButton.largestTextSize)
            .accessibilityShowsLargeContentViewer()
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
    static let largestTextSize = DynamicTypeSize.xxxLarge
}

/// The circle and its icon, at the text size it is given.
private struct FloatingCircle<Label: View>: View {
    let label: Label
    @ScaledMetric(relativeTo: FloatingButton.textStyle) private var diameter = FloatingButton
        .diameter

    var body: some View {
        label
            .labelStyle(.iconOnly)
            .font(.ppFloatingIcon)
            .foregroundStyle(.pp(.textPrimary))
            .frame(width: diameter, height: diameter)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

/// Clear room as tall as a floating button, at the end of a list it floats over, so the last
/// row scrolls clear of it.
public struct FloatingButtonRoom: View {
    public init() { }

    public var body: some View {
        RoomFill()
            .dynamicTypeSize(...FloatingButton.largestTextSize)
            .accessibilityHidden(true)
    }

    private struct RoomFill: View {
        @ScaledMetric(relativeTo: FloatingButton.textStyle) private var height = FloatingButton
            .diameter

        var body: some View {
            Color.clear.frame(height: height)
        }
    }
}

#Preview {
    Button("Add exercise", systemImage: "plus") { }
        .buttonStyle(.floating)
        .padding()
        .background(Color.pp(.background))
}
