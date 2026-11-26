import SwiftUI

/// One of the app's two looks, light or dark, as Settings' two pictures choose it (`Look`).
/// PlusPlus's own colors are the asset catalog's colorsets; with Black belt on, dark draws
/// `Palette.blackBelt` instead.
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
    /// Whether Black belt is on: `Color.pp` draws Black belt's colors rather than PlusPlus's
    /// wherever the color scheme is dark (`drawsBlackBelt`), and PlusPlus's light ones where it
    /// is light.
    @Entry public var isBlackBelt = false

    /// Black belt on, and drawn dark.
    var drawsBlackBelt: Bool {
        isBlackBelt && colorScheme == .dark
    }
}

nonisolated extension EnvironmentValues {
    /// Whether what draws is on a sheet (`sheetGround()`), where Black belt draws a step up
    /// from the screen.
    @Entry var isOnSheet = false
}

extension View {
    /// A sheet's content drawn on a sheet (`isOnSheet`), so Black belt lifts the sheet a step
    /// off the black screen, with a hairline edge; `filled`, under the screen's own color
    /// (`background`), else under what the content draws itself, as Add exercise's navigation
    /// stack does.
    public func sheetGround(filled: Bool = true) -> some View {
        modifier(SheetGround(filled: filled))
    }
}

private struct SheetGround: ViewModifier {
    let filled: Bool
    @Environment(\.isBlackBelt) private var blackBeltOn
    @Environment(\.colorScheme) private var colorScheme

    private var isBlackBelt: Bool {
        blackBeltOn && colorScheme == .dark
    }

    func body(content: Content) -> some View {
        let lifted = content
            .overlay {
                if isBlackBelt {
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
            // and its environment, so Black belt's sheet ground is named here.
            lifted.presentationBackground(
                isBlackBelt ? Color(Palette.blackBeltSheet[.background]) : Color.pp(.background),
            )
        } else {
            lifted
        }
    }
}
