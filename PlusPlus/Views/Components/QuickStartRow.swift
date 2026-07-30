import SwiftUI
import PlusPlusKit

/// Which exercises get a one-tap key in the start tray.
///
/// Device-local, like the active kit pointer: this is a preference about
/// how you use this phone, not part of the program, so it stays out of the
/// interchange.
enum QuickStartPicks {
    static let key = "quickStart.exerciseNames"

    /// Running alone by default. One key plus the "+" reads as an
    /// invitation to add more; four preset keys read as a fixed menu you
    /// have to live with, and most people do one or two sports.
    static let fallback = ["Running"]

    static func names(from raw: String) -> [String] {
        let decoded = raw
            .split(separator: "\u{1F}", omittingEmptySubsequences: true)
            .map(String.init)
        return decoded.isEmpty ? fallback : decoded
    }

    /// Unit-separator joined rather than JSON: `@AppStorage` handles String
    /// natively and this list is a handful of names.
    static func raw(from names: [String]) -> String {
        names.joined(separator: "\u{1F}")
    }
}

/// The start tray's one-tap row: the sports you actually do, plus a key to
/// choose which ones sit here.
///
/// Cardio is mostly spontaneous — nobody authors a template before stepping
/// out the door — and before this, going for a run meant the start tray,
/// then a scratch workout, then the picker, then a search, then a config
/// sheet, then Add, then Start. Seven taps to leave the house.
///
/// Grammar: `RaisedKey`-family caps, because each one COMMITS to starting
/// something. The trailing key is a `CreateRow`-style green bordered cap —
/// it configures the row rather than starting a workout, so it reads as
/// creation, not as a sport.
struct QuickStartRow: View {
    let exercises: [Exercise]
    let onPick: (Exercise) -> Void
    let onEdit: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(exercises, id: \.persistentModelID) { exercise in
                    Button {
                        onPick(exercise)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: exercise.modalitySymbolName)
                                .font(.system(.footnote, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(exercise.name)
                                .font(.system(.footnote, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 42)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius)
                            .strokeBorder(Theme.borderStrong))
                    }
                    .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: Theme.keyRadius, travel: 3))
                    .accessibilityIdentifier("quickStart-\(exercise.name)")
                }

                Button(action: onEdit) {
                    Image(systemName: "plus")
                        .font(.system(.footnote, weight: .bold))
                        // Creation is green (#202) — this key edits the row,
                        // it does not start a workout.
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 42)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius)
                            .strokeBorder(Theme.accent.opacity(0.5)))
                }
                .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: Theme.keyRadius, travel: 3))
                .accessibilityLabel("Choose which workouts appear here")
                .accessibilityIdentifier("quickStartEditButton")
            }
            .padding(.horizontal, 2)
        }
    }
}
