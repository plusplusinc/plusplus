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

    /// Follow a renamed exercise, so a pick keyed to the old name doesn't
    /// silently fall off the row. Name-keying is the fragility here —
    /// this PR's own indoor-bike merge renames a row precisely because a
    /// rename KEEPS the object, and a device-local pick should keep it
    /// too. Called from the two places a catalog name changes: the
    /// exercise editor's save, and the launch merge.
    static func rename(from old: String, to new: String, defaults: UserDefaults = .standard) {
        guard old != new, let stored = defaults.string(forKey: key) else { return }
        var list = names(from: stored)
        guard let index = list.firstIndex(of: old) else { return }
        if list.contains(new) {
            list.remove(at: index)
        } else {
            list[index] = new
        }
        defaults.set(raw(from: list), forKey: key)
    }
}

/// What a quick-start key SAYS: the imperative, not the activity noun
/// ("Run", never "Running" — Dave, build 159). A key is a command, and a
/// gerund on a command reads as a label on a thing rather than a thing
/// to do.
///
/// Authored per built-in name (the FormCues shape), because verbs need
/// judgment a derivation can't make — Cycling rides, Indoor Cycling
/// spins, a pool swim is just "Swim" while open water says where.
/// Customs fall back to their modality's verb; where no honest verb
/// exists (a generic-cardio custom, an elliptical) the name stands — a
/// noun key beats a wrong verb.
enum QuickStartLabel {
    private static let byName: [String: String] = [
        "Running": "Run",
        "Treadmill Run": "Run inside",
        "Walking": "Walk",
        "Hiking": "Hike",
        "Cycling": "Ride",
        "Indoor Cycling": "Spin",
        "Rowing": "Row",
        "Pool Swim": "Swim",
        "Open Water Swim": "Swim open water",
    ]

    static func text(for exercise: Exercise) -> String {
        if let authored = byName[exercise.name] { return authored }
        if let verb = verb(for: exercise.modality) { return verb }
        return exercise.name
    }

    private static func verb(for modality: ExerciseModality) -> String? {
        switch modality {
        case .running: "Run"
        case .walking: "Walk"
        case .hiking: "Hike"
        case .cycling: "Ride"
        case .rowing: "Row"
        case .swimming: "Swim"
        case .jumpRope: "Jump rope"
        case .stairClimbing: "Climb"
        // No honest imperative: "ellipt" is not a thing you tell
        // someone to do, and generic cardio has no verb of its own.
        case .elliptical, .cardio, .strength, .flexibility: nil
        }
    }
}

/// The one-tap row: the sports you actually do, plus a key to choose
/// which ones sit here.
///
/// Cardio is mostly spontaneous — nobody authors a template before stepping
/// out the door — and before this, going for a run meant the start tray,
/// then a scratch workout, then the picker, then a search, then a config
/// sheet, then Add, then Start. Seven taps to leave the house.
///
/// Grammar: `RaisedKey`-family caps, because each one COMMITS to starting
/// something. The trailing key is a `CreateRow`-style green bordered cap —
/// it configures the row rather than starting a workout, so it reads as
/// creation, not as a sport. The scroll runs full-bleed with the surface's
/// 16 pt content margin, so a long row slides under the screen edge
/// instead of clipping at a column boundary.
struct QuickStartRow: View {
    let exercises: [Exercise]
    let onPick: (Exercise) -> Void
    let onEdit: () -> Void

    /// The key's imperative — unless two picks resolve to the same verb
    /// (both climbers, a custom bike beside Cycling), where the colliding
    /// keys fall back to their own names: two keys both saying "Ride"
    /// is a coin flip, and a noun beats a coin flip.
    private func label(for exercise: Exercise) -> String {
        let mine = QuickStartLabel.text(for: exercise)
        let twins = exercises.filter { QuickStartLabel.text(for: $0) == mine }
        return twins.count > 1 ? exercise.name : mine
    }

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
                            Text(label(for: exercise))
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
            // 2 pt of slack so the caps' press travel never clips against
            // the scroll bounds; the surface margin rides contentMargins.
            .padding(.horizontal, 2)
        }
        .contentMargins(.horizontal, 14, for: .scrollContent)
    }
}
