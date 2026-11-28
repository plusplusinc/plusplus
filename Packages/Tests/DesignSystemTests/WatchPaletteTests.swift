import SwiftUI
import Testing
@testable import DesignSystem

/// The Watch's colors are PlusPlus dark's, copied out of the asset catalog, which watchOS reads
/// in one appearance only. A colorset changed without its copy would leave the Watch a shade off.
@Suite("Watch palette")
struct WatchPaletteTests {
    @Test("Every token's Watch color is PlusPlus dark's", arguments: ColorToken.allCases)
    func watchColorIsDarks(token: ColorToken) {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        let dark = Color.pp(token).resolve(in: environment)
        let watch = WatchPalette[token]
        for (drawn, copied) in [
            (dark.red, watch.red), (dark.green, watch.green), (dark.blue, watch.blue),
            (dark.opacity, watch.opacity),
        ] {
            #expect(abs(drawn - copied) < 0.002, "\(token)")
        }
    }
}
