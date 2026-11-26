import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// The person's appearance is kept on the device and read as the app launches. A second `Look`
/// on the same defaults is a relaunch. The stored values are the two people's data: one that
/// names no look opens as Dark rather than failing, and what earlier builds stored opens as the
/// same choice.
@Suite("Look")
struct LookTests {
    private let suite = "LookTests-\(UUID().uuidString)"

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    /// The three parts of the choice, as one value to compare.
    /// Nonisolated, so a test's arguments can build it.
    nonisolated struct Choice: Equatable, Sendable, CustomStringConvertible {
        let appearance: Appearance
        let isAutomatic: Bool
        let isVoid: Bool

        init(_ appearance: Appearance, automatic: Bool = false, void: Bool = false) {
            (self.appearance, isAutomatic, isVoid) = (appearance, automatic, void)
        }

        @MainActor
        init(_ look: Look) {
            self.init(look.appearance, automatic: look.isAutomatic, void: look.isVoid)
        }

        var description: String {
            "\(appearance), automatic \(isAutomatic), Void \(isVoid)"
        }
    }

    @Test("A second Look on the same defaults opens with every choice the first set")
    func choiceSurvivesRelaunch() throws {
        try withDefaults { defaults in
            for appearance in Appearance.allCases {
                for automatic in [false, true] {
                    for void in [false, true] {
                        let look = Look(defaults: defaults)
                        look.appearance = appearance
                        look.isAutomatic = automatic
                        look.isVoid = void
                        let choice = Choice(appearance, automatic: automatic, void: void)
                        #expect(Choice(Look(defaults: defaults)) == choice)
                    }
                }
            }
        }
    }

    @Test("A new install, and a stored look that names none, open on Dark with both switches off")
    func unknownValueFallsBack() throws {
        try withDefaults { defaults in
            #expect(Choice(Look(defaults: defaults)) == Choice(.dark))
            defaults.set("dusk", forKey: Look.appearanceKey)
            #expect(Choice(Look(defaults: defaults)) == Choice(.dark))
        }
    }

    /// The segmented control's four appearances, stored under the one key before the switches.
    @Test(
        "Each of the four stored appearances opens as the same choice, and is rewritten",
        arguments: [
            ("light", Choice(.light)),
            ("dark", Choice(.dark)),
            ("auto", Choice(.dark, automatic: true)),
            ("black-belt", Choice(.dark, void: true)),
        ],
    )
    func fourAppearancesMigrate(stored: String, expected: Choice) throws {
        try withDefaults { defaults in
            defaults.set(stored, forKey: Look.appearanceKey)
            #expect(Choice(Look(defaults: defaults)) == expected)
            #expect(defaults.string(forKey: Look.appearanceKey) == expected.appearance.rawValue)
            #expect(Choice(Look(defaults: defaults)) == expected)
        }
    }

    /// The Void switch under the key the first build with switches wrote.
    @Test("The Void switch stored under its earlier key opens as it was, and moves")
    func earlierSwitchKeyMigrates() throws {
        try withDefaults { defaults in
            for isOn in [false, true] {
                defaults.removeObject(forKey: Look.voidKey)
                defaults.set("dark", forKey: Look.appearanceKey)
                defaults.set(isOn, forKey: "black-belt")
                #expect(Look(defaults: defaults).isVoid == isOn)
                #expect(defaults.object(forKey: "black-belt") == nil)
                #expect(Look(defaults: defaults).isVoid == isOn)
            }
        }
    }

    @Test("Automatic leaves the window free, and Light and Dark hold it")
    func heldSchemes() throws {
        try withDefaults { defaults in
            let look = Look(defaults: defaults)
            look.choose(.light)
            #expect(look.colorScheme == .light)
            look.choose(.dark)
            #expect(look.colorScheme == .dark)
            look.isAutomatic = true
            #expect(look.colorScheme == nil)
        }
    }

    /// As iOS's own Display & Brightness: with Automatic on the pictures show the phone's look,
    /// a picture's tap holds it, and turning Automatic off keeps the look in effect.
    @Test("Automatic shows the phone's look; a picture or turning it off holds what shows")
    func automaticAndPictures() throws {
        try withDefaults { defaults in
            let look = Look(defaults: defaults)
            look.choose(.dark)
            look.setAutomatic(true, phone: .light)
            #expect(look.shown(phone: .light) == .light)
            #expect(look.shown(phone: .dark) == .dark)
            look.setAutomatic(false, phone: .light)
            #expect(Choice(look) == Choice(.light))
            look.setAutomatic(true, phone: .light)
            look.choose(.dark)
            #expect(Choice(look) == Choice(.dark))
        }
    }

    /// The switch only changes a dark app, so it is offered only where the app can be dark; its
    /// value is kept while it is not, so it comes back as it was.
    @Test("Void is offered only where the app can be dark, and kept while it isn't")
    func voidOffered() throws {
        try withDefaults { defaults in
            let look = Look(defaults: defaults)
            look.choose(.dark)
            look.isVoid = true
            #expect(look.offersVoid)
            look.choose(.light)
            #expect(!look.offersVoid)
            #expect(look.isVoid)
            look.isAutomatic = true
            #expect(look.offersVoid)
        }
    }
}
