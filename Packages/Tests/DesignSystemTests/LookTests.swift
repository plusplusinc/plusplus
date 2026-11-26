import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// The person's appearance is kept on the device and read as the app launches. A second `Look`
/// on the same defaults is a relaunch. The stored value is the two people's data: one that names
/// no appearance opens as Dark rather than failing.
@Suite("Look")
struct LookTests {
    private let suite = "LookTests-\(UUID().uuidString)"

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test("A second Look on the same defaults opens with each appearance the first set")
    func choiceSurvivesRelaunch() throws {
        try withDefaults { defaults in
            for appearance in Appearance.allCases {
                Look(defaults: defaults).appearance = appearance
                #expect(Look(defaults: defaults).appearance == appearance)
            }
        }
    }

    @Test("A new install, and a stored value that names no appearance, open on Dark")
    func unknownValueFallsBack() throws {
        try withDefaults { defaults in
            #expect(Look(defaults: defaults).appearance == .dark)
            defaults.set("dusk", forKey: Look.appearanceKey)
            #expect(Look(defaults: defaults).appearance == .dark)
        }
    }

    @Test("Light and Dark hold the window, Auto follows the phone, and Black belt holds it dark")
    func heldSchemes() {
        #expect(Appearance.light.colorScheme == .light)
        #expect(Appearance.dark.colorScheme == .dark)
        #expect(Appearance.auto.colorScheme == nil)
        #expect(Appearance.blackBelt.colorScheme == .dark)
    }
}
