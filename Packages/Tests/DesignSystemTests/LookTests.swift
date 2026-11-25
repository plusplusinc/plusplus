import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// The person's appearance and theme are kept on the device and read as the app launches. A
/// second `Look` on the same defaults is a relaunch. The stored ids are the two people's data:
/// one that names no theme opens as PlusPlus rather than failing.
@Suite("Look")
struct LookTests {
    private let suite = "LookTests-\(UUID().uuidString)"

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test(
        "A second Look on the same defaults opens with the appearance and theme the first set",
    )
    func choicesSurviveRelaunch() throws {
        try withDefaults { defaults in
            let first = Look(defaults: defaults)
            first.appearance = .light
            first.theme = .solarized
            let relaunched = Look(defaults: defaults)
            #expect(relaunched.appearance == .light)
            #expect(relaunched.theme == .solarized)
        }
    }

    @Test("A stored id that names no theme opens as PlusPlus, and a new install on Dark")
    func unknownValuesFallBack() throws {
        try withDefaults { defaults in
            #expect(Look(defaults: defaults).appearance == .dark)
            #expect(Look(defaults: defaults).theme == .plusPlus)
            defaults.set("sepia", forKey: Look.themeKey)
            defaults.set("dusk", forKey: Look.appearanceKey)
            let look = Look(defaults: defaults)
            #expect(look.theme == .plusPlus)
            #expect(look.appearance == .dark)
        }
    }

    @Test("Every shipped theme's stored id reads back as that theme, and no two share one")
    func everyIdReadsBack() {
        for theme in Theme.all {
            #expect(Theme.stored(id: theme.id) == theme, "\(theme.name)'s id is \(theme.id)")
        }
        #expect(Set(Theme.all.map(\.id)).count == Theme.all.count)
    }

    @Test("A theme with both looks is held to the appearance, and to nothing on Auto")
    func bothLooksFollowAppearance() {
        #expect(Theme.nord.colorScheme(for: .light) == .light)
        #expect(Theme.nord.colorScheme(for: .dark) == .dark)
        #expect(Theme.nord.colorScheme(for: .auto) == nil)
    }

    @Test("A dark-only theme is held dark whatever the appearance, and draws the same in light")
    func darkOnlyStaysDark() {
        for appearance in Appearance.allCases {
            #expect(Theme.dracula.colorScheme(for: appearance) == .dark)
        }
        var light = EnvironmentValues()
        light.colorScheme = .light
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        for token in ColorToken.allCases {
            #expect(Theme.dracula.resolve(token, in: light) == Theme.dracula.resolve(
                token,
                in: dark,
            ))
        }
    }
}
