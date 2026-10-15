import SwiftUI

extension View {
    /// A raised key: a cap of `fill` standing on a plate of the same shape, which shows as a
    /// strip under its bottom edge. Pressing sinks the cap onto the plate, which stays put, so
    /// nothing around the key moves. A key that can't be used lies flat on the plate's level,
    /// with no plate, dimmed.
    func raisedKey(fill: Color, outlined: Bool = false, isPressed: Bool, isEnabled: Bool = true)
        -> some View
    {
        let shape = RoundedRectangle(cornerRadius: Radius.key)
        return background(shape.fill(fill))
            .overlay {
                if outlined {
                    shape.strokeBorder(.pp(.borderStrong))
                }
            }
            .contentShape(shape)
            .offset(y: isPressed || !isEnabled ? RaisedKey.travel : 0)
            .keyPressAnimation(isPressed: isPressed)
            .background {
                if isEnabled {
                    shape.fill(.pp(.borderStrong)).offset(y: RaisedKey.travel)
                }
            }
            .padding(.bottom, RaisedKey.travel)
            .opacity(isEnabled ? 1 : 0.35)
    }
}

enum RaisedKey {
    /// How far a cap stands above its plate, and so how far a press sinks it.
    static let travel: CGFloat = 4
}
