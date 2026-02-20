import SwiftUI

// Radix Colors — Slate scale
// https://www.radix-ui.com/colors/docs/palette-composition/scales
extension Color {
    static let slate1 = Color(uiColor: .slate(light: 0xfcfcfd, dark: 0x111113))
    static let slate2 = Color(uiColor: .slate(light: 0xf9f9fb, dark: 0x18191b))
    static let slate3 = Color(uiColor: .slate(light: 0xf0f0f3, dark: 0x212225))
    static let slate4 = Color(uiColor: .slate(light: 0xe8e8ec, dark: 0x272a2d))
    static let slate5 = Color(uiColor: .slate(light: 0xe0e1e6, dark: 0x2e3135))
    static let slate6 = Color(uiColor: .slate(light: 0xd9d9e0, dark: 0x363a3f))
    static let slate7 = Color(uiColor: .slate(light: 0xcdced6, dark: 0x43484e))
    static let slate8 = Color(uiColor: .slate(light: 0xb9bbc6, dark: 0x5a6169))
    static let slate9 = Color(uiColor: .slate(light: 0x8b8d98, dark: 0x696e77))
    static let slate10 = Color(uiColor: .slate(light: 0x80838d, dark: 0x777b84))
    static let slate11 = Color(uiColor: .slate(light: 0x60646c, dark: 0xb0b4ba))
    static let slate12 = Color(uiColor: .slate(light: 0x1c2024, dark: 0xedeef0))
}

private extension UIColor {
    static func slate(light: UInt, dark: UInt) -> UIColor {
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
