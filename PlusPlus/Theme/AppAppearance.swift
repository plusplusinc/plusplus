import SwiftUI

/// The appearance setting (#97): follow the device, or pin dark/light.
/// Supersedes the v2 dark-only decision now that Theme is adaptive.
enum AppAppearance: String, CaseIterable {
    case system
    case dark
    case light

    static let storageKey = "appearance"

    var label: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    /// nil means "follow the device".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}
