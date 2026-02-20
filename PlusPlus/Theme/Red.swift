import SwiftUI

// Radix Colors — Red scale
// https://www.radix-ui.com/colors/docs/palette-composition/scales
extension Color {
    static let red1 = Color(uiColor: .radixRed(light: 0xfffcfc, dark: 0x191111))
    static let red2 = Color(uiColor: .radixRed(light: 0xfff7f7, dark: 0x201314))
    static let red3 = Color(uiColor: .radixRed(light: 0xfeebec, dark: 0x3b1219))
    static let red4 = Color(uiColor: .radixRed(light: 0xffdbdc, dark: 0x500f1c))
    static let red5 = Color(uiColor: .radixRed(light: 0xffcdce, dark: 0x611623))
    static let red6 = Color(uiColor: .radixRed(light: 0xfdbdbe, dark: 0x72232d))
    static let red7 = Color(uiColor: .radixRed(light: 0xf4a9aa, dark: 0x8c333a))
    static let red8 = Color(uiColor: .radixRed(light: 0xeb8e90, dark: 0xb54548))
    static let red9 = Color(uiColor: .radixRed(light: 0xe5484d, dark: 0xe5484d))
    static let red10 = Color(uiColor: .radixRed(light: 0xdc3e42, dark: 0xec5d5e))
    static let red11 = Color(uiColor: .radixRed(light: 0xce2c31, dark: 0xff9592))
    static let red12 = Color(uiColor: .radixRed(light: 0x641723, dark: 0xffd1d9))
}

private extension UIColor {
    static func radixRed(light: UInt, dark: UInt) -> UIColor {
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
