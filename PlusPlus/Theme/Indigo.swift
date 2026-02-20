import SwiftUI

// Radix Colors — Indigo scale
// https://www.radix-ui.com/colors/docs/palette-composition/scales
extension Color {
    static let indigo1 = Color(uiColor: .radixIndigo(light: 0xfdfdfe, dark: 0x11131f))
    static let indigo2 = Color(uiColor: .radixIndigo(light: 0xf7f9ff, dark: 0x141726))
    static let indigo3 = Color(uiColor: .radixIndigo(light: 0xedf2fe, dark: 0x182449))
    static let indigo4 = Color(uiColor: .radixIndigo(light: 0xe1e9ff, dark: 0x1d2e62))
    static let indigo5 = Color(uiColor: .radixIndigo(light: 0xd2deff, dark: 0x253974))
    static let indigo6 = Color(uiColor: .radixIndigo(light: 0xc1d0ff, dark: 0x304384))
    static let indigo7 = Color(uiColor: .radixIndigo(light: 0xabbdf9, dark: 0x3a4f97))
    static let indigo8 = Color(uiColor: .radixIndigo(light: 0x8da4ef, dark: 0x435db1))
    static let indigo9 = Color(uiColor: .radixIndigo(light: 0x3e63dd, dark: 0x3e63dd))
    static let indigo10 = Color(uiColor: .radixIndigo(light: 0x3358d4, dark: 0x5472e4))
    static let indigo11 = Color(uiColor: .radixIndigo(light: 0x3a5bc7, dark: 0x9eb1ff))
    static let indigo12 = Color(uiColor: .radixIndigo(light: 0x1f2d5c, dark: 0xd6e1ff))
}

private extension UIColor {
    static func radixIndigo(light: UInt, dark: UInt) -> UIColor {
        UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}
