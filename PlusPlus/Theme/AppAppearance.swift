import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: Self { self }

    var displayName: String {
        rawValue.capitalized
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}
