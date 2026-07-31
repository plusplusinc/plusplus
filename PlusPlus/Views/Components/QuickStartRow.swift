import SwiftUI
import PlusPlusKit

/// Which exercises get a one-tap key in Today's pinned band.
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
/// creation, not as a sport.
///
/// ⚠️ The row NEVER scrolls (Dave, build 159: "the horizontal scroll isn't
/// great") — hidden overflow in a pinned band has no affordance at all. It
/// fits what it can and collapses the tail into an "N more" key, exactly
/// the muscle tags' rule (`OverflowCapsuleRow`, 2026-07-19) at key scale:
/// widths from `UIFont` metrics, never a geometry probe (the morph law).
/// "N more" is a Menu of the hidden sports, so every pick stays reachable —
/// the visible keys at one tap, the tail at two.
struct QuickStartRow: View {
    let exercises: [Exercise]
    let onPick: (Exercise) -> Void
    /// The scratch start — the one way to begin that had no other home
    /// once the play key died (Dave, build 159: the today card and the
    /// Routines tab already serve the tray's other rows). It LEADS the
    /// rack: the universal start anchors, the picked sports follow.
    let onWorkOut: () -> Void
    let onEdit: () -> Void

    @State private var containerWidth: CGFloat = 0

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
        let fit = fitting(width: containerWidth)
        HStack(spacing: 8) {
            trainKey
            ForEach(fit.visible, id: \.persistentModelID) { exercise in
                sportKey(exercise)
            }
            if !fit.hidden.isEmpty {
                moreKey(fit.hidden)
            }
            editKey
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Container width from a background reader, the OverflowCapsuleRow
        // idiom: reading into state from a BACKGROUND avoids the layout
        // feedback loop, and nothing here observes scroll geometry.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in containerWidth = width }
            }
        )
        .padding(.horizontal, 16)
    }

    /// The scratch session: walk in, start logging, keep the result as a
    /// routine at the finish if it earned it (#239). "Train" is the
    /// imperative for the workout that isn't one sport — the voice's own
    /// verb — and the dashed square is the build-as-you-go glyph the
    /// empty-workout path has always worn.
    private var trainKey: some View {
        Button(action: onWorkOut) {
            HStack(spacing: 7) {
                Image(systemName: "plus.square.dashed")
                    .font(.system(.footnote, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Train")
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
        .accessibilityLabel("Train, build the workout as you go")
        .accessibilityIdentifier("quickStartTrain")
    }

    private func sportKey(_ exercise: Exercise) -> some View {
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

    /// The overflow: a Menu of the sports that didn't fit, each starting
    /// its workout exactly like a visible key. Key chrome in secondary ink
    /// (a continuation, not a sport), no press travel — Menus manage their
    /// own presentation, the FacetChip precedent.
    private func moreKey(_ hidden: [Exercise]) -> some View {
        Menu {
            ForEach(hidden, id: \.persistentModelID) { exercise in
                Button(label(for: exercise)) { onPick(exercise) }
            }
        } label: {
            Text("\(hidden.count) more")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 42)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius)
                    .strokeBorder(Theme.borderStrong))
        }
        .accessibilityLabel("\(hidden.count) more sports")
        .accessibilityIdentifier("quickStartMore")
    }

    private var editKey: some View {
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

    // MARK: - Fitting

    /// Greedy left-to-right fit, reserving the edit key always and the
    /// "N more" key whenever anything is left over. At least one sport
    /// key always shows — one real key plus "N more" beats only chrome.
    private func fitting(width: CGFloat) -> (visible: [Exercise], hidden: [Exercise]) {
        guard width > 0, exercises.count > 1 else { return (exercises, []) }
        let spacing: CGFloat = 8
        let widths = exercises.map { Self.keyWidth(label(for: $0), hasGlyph: true) }
        // The Train and edit keys always show; sports fit around them.
        var used: CGFloat = Self.keyWidth("Train", hasGlyph: true) + spacing + Self.editKeyWidth
        var shown = 0
        for index in exercises.indices {
            let next = used + spacing + widths[index]
            let remaining = exercises.count - (shown + 1)
            let reserve = remaining > 0 ? spacing + Self.keyWidth("\(remaining) more", hasGlyph: false) : 0
            if next + reserve <= width {
                used = next
                shown += 1
            } else {
                break
            }
        }
        if shown == 0 { shown = 1 }
        return (Array(exercises.prefix(shown)), Array(exercises.dropFirst(shown)))
    }

    /// A key's rendered width from `UIFont` metrics — mirrors the key's
    /// footnote-semibold text, the 14 pt pads, and the glyph's share.
    /// An estimate, exactly like the tag row's: never a geometry probe.
    private static func keyWidth(_ text: String, hasGlyph: Bool) -> CGFloat {
        let base = UIFont.preferredFont(forTextStyle: .footnote)
        // ⚠️ `.rawValue`, not the Weight struct: the traits dictionary
        // wants an NSNumber, and a boxed Swift struct is silently ignored
        // — the measurement would resolve at REGULAR while the key
        // renders semibold, under-measuring every label (swift-reviewer).
        let font = UIFont(
            descriptor: base.fontDescriptor.addingAttributes(
                [.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold.rawValue]]
            ),
            size: base.pointSize
        )
        var width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        // 1.6 em: the cardio `figure.*` symbols this row actually renders
        // (pool.swim, outdoor.cycle, mixed.cardio) run well past square —
        // the tag row's 1.2 em was calibrated on a near-square calendar
        // glyph. Overestimating is the safe side: a key drops into
        // "N more" one width early instead of truncating mid-label.
        if hasGlyph { width += font.pointSize * 1.6 + 7 }
        return width + 28 + 2
    }

    /// The green "+" cap: a bold footnote glyph between 14 pt pads.
    private static var editKeyWidth: CGFloat {
        UIFont.preferredFont(forTextStyle: .footnote).pointSize * 1.2 + 28 + 2
    }
}
