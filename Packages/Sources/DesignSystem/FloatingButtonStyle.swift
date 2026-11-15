import SwiftUI

/// A round button floating over a screen's content: its label's icon alone, dark on a solid
/// green 56 pt circle, the same on every state of the screen. Green is for data and the +. A
/// press dims it, as it does a key, so nothing around it moves. The circle scales with the icon's
/// text style up to the largest size short of the accessibility sizes, as a bar's buttons stop
/// there; past it, a long press shows the label in the large content viewer. Scaled on, it grew
/// past twice its size over the rows it floats on. `primaryKeyBar(…floating:)` places one above
/// the key.
public struct FloatingButtonStyle: ButtonStyle {
    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        FloatingCircle(label: configuration.label)
            .keyPress(isPressed: configuration.isPressed)
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
            .foregroundStyle(.pp(.onPrimaryKey))
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(.pp(.accent)))
            .contentShape(.circle)
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

/// `floating` in the floating style, its right edge on `key`'s and `gap` above it, over `key`
/// laid out unseen, `sides` in from the screen's sides and its bottom `bottom` up from the safe
/// area's. Laid out over the copy rather than placed from its measured height, so when the key
/// it sits over changes in an animated update, the button moves under that update's animation:
/// placed from a measurement, which lands after the update, it jumped. While `isLow`, with no
/// copy, its bottom sits where the key's ledge's bottom would, and it rises to its place above
/// the key, or comes back down, on the update that brings the key in or takes it away.
struct FloatingPlace<Key: View, Floating: View>: View {
    let key: Key
    let floating: Floating
    let gap: CGFloat
    let sides: CGFloat
    let bottom: CGFloat
    let isLow: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: gap) {
            floating
                .buttonStyle(.floating)
                .hiddenBehindDrawer()
            if !isLow {
                key.hidden()
            }
        }
        .padding(.horizontal, sides)
        .padding(.bottom, bottom)
        // Trailing, for when there is no copy of the key to span the width.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .ignoresSafeArea(.keyboard)
    }
}

#Preview {
    Button("Add exercise", systemImage: "plus") { }
        .buttonStyle(.floating)
        .padding()
        .background(Color.pp(.background))
}
