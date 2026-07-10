import SwiftUI

/// Quiet Arcade on the wrist: the watch can't import the app's Theme
/// (separate target), so the brand hues live here — values mirror
/// Theme.swift's dark side. The system's black canvas stays (OLED and
/// watchOS convention beat the phone's warm charcoal at this size);
/// the hue jobs and the press grammar carry the identity.
enum WatchTheme {
    /// Data green (dark-scheme `accent`): the ++ mark, deltas, live
    /// progress.
    static let accent = Color(red: 0x46 / 255.0, green: 0xD1 / 255.0, blue: 0x7C / 255.0)
    /// Completion purple (dark-scheme `done`).
    static let done = Color(red: 0xA3 / 255.0, green: 0x71 / 255.0, blue: 0xF7 / 255.0)
    /// Cream action fill + its ink content (dark-scheme
    /// `primaryFill`/`onPrimary`): actions are ink/cream, never green.
    static let primaryFill = Color(red: 0xF0 / 255.0, green: 0xED / 255.0, blue: 0xE6 / 255.0)
    static let onPrimary = Color(red: 0x16 / 255.0, green: 0x16 / 255.0, blue: 0x16 / 255.0)
    /// Raised-key base plate (dark `borderStrong`).
    static let plate = Color(red: 0x4E / 255.0, green: 0x4B / 255.0, blue: 0x43 / 255.0)
    /// Secondary key cap / unfilled progress blocks (dark
    /// `surfaceRaised`).
    static let surfaceRaised = Color(red: 0x34 / 255.0, green: 0x32 / 255.0, blue: 0x2D / 255.0)
}

/// The press grammar at 40 mm: an opaque cap sinks 2 pt onto a fixed
/// base plate, 0.06 s ease-out — the phone's raised key, quiet-key
/// travel (3 pt reads clunky at watch sizes).
struct WatchRaisedKeyStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 2 : 0)
            .padding(.bottom, 2)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(WatchTheme.plate)
                    .padding(.top, 2)
            }
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
    }
}
