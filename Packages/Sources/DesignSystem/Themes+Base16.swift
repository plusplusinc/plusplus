import SwiftUI

nonisolated extension Theme {
    public static let nord = Theme(
        id: "nord",
        name: "Nord",
        looks: .darkOnly(Palette(Base16.nord, isDark: true)),
    )
}

/// The palettes, each scheme's sixteen colors as given, copied from tinted-theming/schemes
/// (branch spec-0.11, `base16/`), under its MIT license:
///
/// Copyright (c) 2022 Tinted Theming (https://github.com/tinted-theming)
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy of this software
/// and associated documentation files (the "Software"), to deal in the Software without
/// restriction, including without limitation the rights to use, copy, modify, merge, publish,
/// distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
/// Software is furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in all copies or
/// substantial portions of the Software.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
/// BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
/// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
/// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
///
/// Each scheme's author is named on it.
nonisolated extension Base16 {
    /// `nord`, by arcticicestudio.
    static let nord = Base16([
        0x2E3440, 0x3B4252, 0x434C5E, 0x4C566A, 0xD8DEE9, 0xE5E9F0, 0xECEFF4, 0x8FBCBB,
        0xBF616A, 0xD08770, 0xEBCB8B, 0xA3BE8C, 0x88C0D0, 0x81A1C1, 0xB48EAD, 0x5E81AC,
    ])
}
