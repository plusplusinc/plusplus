import SwiftUI

/// One of the app's two looks, light or dark, as Settings' two pictures choose it (`Look`).
/// PlusPlus's own colors are the asset catalog's colorsets; with Void on, dark draws
/// `Palette.void` instead.
public nonisolated enum Appearance: String, CaseIterable, Sendable {
    case light
    case dark

    /// A new install, and a stored value that names none: dark, as the app was before the
    /// choice existed, until the light palette has had its review.
    public static let initial = Self.dark

    public init(_ scheme: ColorScheme) {
        self = scheme == .light ? .light : .dark
    }

    public var name: String {
        switch self {
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    public var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}

nonisolated extension EnvironmentValues {
    /// Whether Void is on: `Color.pp` draws Void's colors rather than PlusPlus's
    /// wherever the color scheme is dark (`drawsVoid`), and PlusPlus's light ones where it
    /// is light.
    @Entry public var isVoid = false

    /// Void on, and drawn dark.
    var drawsVoid: Bool {
        isVoid && colorScheme == .dark
    }
}

nonisolated extension EnvironmentValues {
    /// Whether what draws is on a sheet (`sheetGround()`), where Void draws a step up
    /// from the screen.
    @Entry var isOnSheet = false
}

extension View {
    /// A sheet's content drawn on a sheet (`isOnSheet`), so Void lifts the sheet a step
    /// off the black screen, with a hairline edge; `filled`, under the screen's own color
    /// (`background`), else under what the content draws itself, as Add exercise's navigation
    /// stack does.
    public func sheetGround(filled: Bool = true) -> some View {
        modifier(SheetGround(filled: filled))
    }
}

private struct SheetGround: ViewModifier {
    let filled: Bool
    @Environment(\.isVoid) private var voidOn
    @Environment(\.colorScheme) private var colorScheme

    private var isVoid: Bool {
        voidOn && colorScheme == .dark
    }

    func body(content: Content) -> some View {
        let lifted = content
            .overlay {
                if isVoid {
                    // In the step a cell on the sheet takes, as iOS edges its own sheets over
                    // black. Centered on the sheet's outline, which clips its outer half: a
                    // point shows.
                    ConcentricRectangle()
                        .stroke(.pp(.surfaceRaised), lineWidth: 2)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .environment(\.isOnSheet, true)
        if filled {
            // A color, not a view: as a view, the system drew the dimmed screen around the sheet
            // a step apart from the color's. The system draws it outside the sheet's content
            // and its environment, so Void's sheet ground is named here.
            lifted.presentationBackground(
                isVoid ? Color(Palette.voidSheet[.background]) : Color.pp(.background),
            )
        } else {
            lifted
        }
    }
}
