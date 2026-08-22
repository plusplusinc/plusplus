import SwiftUI

/// The press grammar for anything that commits or navigates: an opaque cap sitting proud of a
/// fixed base plate, with the plate visible as a strip under the bottom edge. Pressing sinks the
/// cap onto the plate; the plate never moves.
///
/// Flat controls — chips, toggles, list rows — stay flat. Their state change is the feedback.
///
/// The style owns only the mechanics. The caller styles the label, and **the cap must be opaque**
/// (`ppBackground`, `ppSurface`, or `ppPrimaryFill`) or the plate shows through it at rest.
public struct RaisedKeyStyle: ButtonStyle {
    private let plate: Color
    private let cornerRadius: CGFloat
    private let travel: CGFloat

    @Environment(\.isEnabled) private var isEnabled

    public init(plate: Color, cornerRadius: CGFloat = Radius.key, travel: CGFloat = 4) {
        self.plate = plate
        self.cornerRadius = cornerRadius
        self.travel = travel
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed && isEnabled ? travel : 0)
            .padding(.bottom, travel)
            .background {
                // A disabled key lies flat: no plate, nothing to press onto.
                if isEnabled {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(plate)
                        .padding(.top, travel)
                }
            }
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == RaisedKeyStyle {
    /// Secondary key: a light cap on the standard plate.
    public static func raisedKey(cornerRadius: CGFloat = Radius.key) -> RaisedKeyStyle {
        RaisedKeyStyle(plate: .ppBorder, cornerRadius: cornerRadius)
    }

    /// Primary key: a `ppPrimaryFill` cap on the stronger plate.
    public static func raisedPrimaryKey(cornerRadius: CGFloat = Radius.key) -> RaisedKeyStyle {
        RaisedKeyStyle(plate: .ppBorderStrong, cornerRadius: cornerRadius)
    }
}
