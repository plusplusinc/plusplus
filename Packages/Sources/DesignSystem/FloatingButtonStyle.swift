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

/// `floating` in the floating style at its low place, `sides` in from the screen's sides and its
/// bottom `bottom` up from the safe area's, where a key's ledge's bottom is, drawn `lift` above
/// it, under no animation of its own: the lift is worked out from the key as drawn that frame
/// (`KeyReach.floatingLift`), and animated, the button would trail the key. While `isLow`, as
/// with no key in sight, with Reduce Motion it fades out of one place and into the other. Gone
/// low, it takes no tap until it has rested there a while (`LowSettle`).
struct FloatingPlace<Floating: View>: View {
    let floating: Floating
    let sides: CGFloat
    let bottom: CGFloat
    var lift: CGFloat = 0
    let isLow: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        floating
            .buttonStyle(.floating)
            .hiddenBehindDrawer()
            .animation(nil) { $0.offset(y: -lift) }
            // Another button in each place, so it crossfades rather than travels; inside the
            // id, the one going keeps the place it had.
            .id(reduceMotion && isLow)
            .transition(.opacity)
            // Outside the id, so the crossfade keeps the wait.
            .modifier(LowSettle(isLow: isLow))
            .padding(.horizontal, sides)
            .padding(.bottom, bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .ignoresSafeArea(.keyboard)
    }
}

/// Where a bottom key sits on a screen, shared by the key's bar (`primaryKeyBar`) and a floating
/// button with no key under it, so the two cannot drift.
enum KeyInsets {
    /// The key's inset from the screen's sides: `lowInset`, and with no home indicator, as far as
    /// content is inset. At the accessibility sizes, as far as content is inset, so its label
    /// has the width to stay on one line.
    static func side(bottomInset: CGFloat, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        bottomInset > 0 && !dynamicTypeSize.isAccessibilitySize
            ? PrimaryKeyButtonStyle.lowInset
            : Spacing.md
    }

    /// The ledge's bottom above the screen's bottom: `lowInset`, and with no home indicator, the
    /// bar's own bottom.
    static func ledgeLift(bottomInset: CGFloat) -> CGFloat {
        bottomInset > 0 ? PrimaryKeyButtonStyle.lowInset : 0
    }
}

extension View {
    /// `button` floating at the screen's bottom trailing corner in the floating style, where the
    /// workout screen's + sits with no key under it: its bottom where a key's ledge would be, as
    /// far in from the side as a key.
    public func floatingButton(_ button: some View) -> some View {
        modifier(FloatingButtonPlacement(button: button))
    }
}

private struct FloatingButtonPlacement<Floating: View>: ViewModifier {
    let button: Floating
    @State private var bottomInset: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            .overlay {
                FloatingPlace(
                    floating: button,
                    sides: KeyInsets.side(
                        bottomInset: bottomInset,
                        dynamicTypeSize: dynamicTypeSize,
                    ),
                    bottom: KeyInsets.ledgeLift(bottomInset: bottomInset) - bottomInset,
                    isLow: true,
                )
            }
            .background {
                Color.clear.onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.bottom) {
                    bottomInset = $0
                }
            }
    }
}

#Preview {
    Button("Add exercise", systemImage: "plus") { }
        .buttonStyle(.floating)
        .padding()
        .background(Color.pp(.background))
}
