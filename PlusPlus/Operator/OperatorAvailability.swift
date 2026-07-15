import Foundation
import FoundationModels
import SwiftUI

/// The one place Operator reads Foundation Models availability. Each
/// unavailable reason has its own explainer (rendered inside the tray in
/// Operator's voice) and its own hero-card status word — the entry point
/// is ALWAYS visible; unavailable states explain themselves on tap.
enum OperatorAvailability: Equatable {
    case ready
    case deviceNotEligible
    case intelligenceOff
    case downloading

    static func current() -> OperatorAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .intelligenceOff
        case .unavailable(.modelNotReady):
            return .downloading
        case .unavailable:
            // Unknown future reason: treat like a transient not-ready.
            return .downloading
        }
    }

    /// The hero card's trailing mono word. Quiet when everything is
    /// fine (presence IS the statement, the GitHub-row rule).
    var statusWord: String? {
        switch self {
        case .ready: nil
        case .deviceNotEligible: "unavailable"
        case .intelligenceOff: "off"
        case .downloading: "downloading"
        }
    }

    /// The in-tray explainer body; nil when ready (the chat shows).
    var explanation: String? {
        switch self {
        case .ready: nil
        case .deviceNotEligible: OperatorPersona.deviceNotEligible
        case .intelligenceOff: OperatorPersona.intelligenceOff
        case .downloading: OperatorPersona.modelDownloading
        }
    }

    /// Whether the explainer offers the Settings deep link (the
    /// Apple-Intelligence opt-in lives there).
    var offersSettingsLink: Bool {
        self == .intelligenceOff
    }
}
