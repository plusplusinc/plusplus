import SwiftUI

/// How the app looks: held light, held dark, following the phone, or Black belt, true black
/// whatever the phone's appearance. Light, Dark, and Auto draw PlusPlus's own colors, the asset
/// catalog's colorsets; Black belt draws `Palette.blackBelt`.
public nonisolated enum Appearance: String, CaseIterable, Sendable {
    case light
    case dark
    case auto
    case blackBelt = "black-belt"

    /// A new install, and a stored value that names none: dark, as the app was before the
    /// choice existed, until the light palette has had its review.
    public static let initial = Self.dark

    public var name: String {
        switch self {
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        case .auto: String(localized: "Auto")
        case .blackBelt: String(localized: "Black belt")
        }
    }

    /// What the window is held to: the appearance's, Black belt's dark, or nothing on Auto, so
    /// it follows the phone.
    public var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark, .blackBelt: .dark
        case .auto: nil
        }
    }
}

nonisolated extension EnvironmentValues {
    /// Whether `Color.pp` draws Black belt's colors rather than PlusPlus's.
    @Entry public var isBlackBelt = false
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
    @Environment(\.isBlackBelt) private var isBlackBelt

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
            // a step apart from the color's.
            lifted.presentationBackground(Color(TokenColor(token: .background, onSheet: true)))
        } else {
            lifted
        }
    }
}
