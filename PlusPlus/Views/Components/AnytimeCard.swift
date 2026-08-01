import SwiftUI
import PlusPlusKit

/// The rail's ANYTIME entry (Dave, build 160): quick start as a card on
/// the timeline — below the future items, above whatever today holds,
/// every day. The dashed shell is the offer grammar at card scale (the
/// dashed node beside it, the future cards' "not yet" dash): outlined,
/// unfilled, not yet a thing.
///
/// The shell is LIVE. Tapping a key GROWS it into a panel filling the
/// card — a sport gets its last outing, preset target chips and Start;
/// Train gets the scratch start and the routine handoff; "N more" gets
/// the sports that didn't fit, each one level deeper. The back key
/// shrinks the panel home. At the end of the morph the panel's solid
/// border has OVERTAKEN the dashed one; the dashes fade back in on the
/// way out.
///
/// ⚠️ The morph is `matchedGeometryEffect` on the CHROME ONLY — the key's
/// background pairs with the panel's background; content fades. Matching
/// whole views makes text reflow mid-flight (jitter), and the alternative
/// (measuring the key's frame into state for a hand FLIP) is BANNED here:
/// Today lives in the TabView subtree, where writing state during layout
/// breaks the search-role morph (nav-diag 4e, navigation.md).
/// `matchedGeometryEffect` is a layout-time effect with no state writes.
///
/// ⚠️ The green + opens the picker SHEET, not an in-place panel: the
/// picks come from the whole cardio catalog, and a multi-select is a
/// searchable list, not a chip grid (ui-interaction.md).
struct AnytimeCard: View {
    let exercises: [Exercise]
    /// "last · 5.1 km · 28 min" for a sport panel, from history. nil
    /// renders nothing (a first outing needs no caption).
    let lastOuting: (Exercise) -> String?
    /// Start now with the panel's chip applied (Open = no target).
    let onStart: (SessionExerciseConfig) -> Void
    /// The full config sheet — the escape for a target the chips don't
    /// carry. The triad law lives there; chips stay presets.
    let onCustom: (Exercise) -> Void
    let onStartEmpty: () -> Void
    /// Hands off to the Routines tab — a pointer, never a second copy
    /// of the library (the start tray died for duplicating surfaces).
    let onChooseRoutine: () -> Void
    let onEdit: () -> Void

    @Namespace private var morph
    @State private var stage: Stage = .rack
    /// The picked preset per open panel; nil is Open (no target).
    /// Reset on every stage change.
    @State private var pickedPreset: QuickStartPresets.Preset?
    @State private var containerWidth: CGFloat = 0

    /// Panels key on the exercise NAME: stable, Equatable, and already
    /// how the picks themselves are stored.
    enum Stage: Equatable {
        case rack
        case sport(String)
        case train
        case more
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch stage {
            case .rack:
                rack
                    .transition(.opacity)
            case .sport(let name):
                if let exercise = exercises.first(where: { $0.name == name }) {
                    panel(sourceID: "key-\(name)") { sportPanel(exercise) }
                } else {
                    // The pick vanished mid-open (a rename landing from
                    // another screen) — fall home rather than render an
                    // empty shell.
                    Color.clear.frame(height: 1).onAppear { stage = .rack }
                }
            case .train:
                panel(sourceID: "key-train") { trainPanel }
            case .more:
                panel(sourceID: "key-more") { morePanel }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The offer's dashed boundary. It fades UNDER the growing panel
        // (whose solid border becomes the card's edge) and returns as
        // the panel shrinks home — while open there is no dashed edge.
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .opacity(stage == .rack ? 1 : 0)
        )
        .animation(Theme.Anim.standard, value: stage == .rack)
    }

    private func open(_ next: Stage) {
        pickedPreset = nil
        // The selection spring, not a flourish: this is the app's
        // reveal-in-place motion. The token already resolves Reduce
        // Motion to a near-instant swap.
        withAnimation(Theme.Anim.selection) { stage = next }
    }

    // MARK: - The rack

    private var rack: some View {
        let fit = fitting(width: containerWidth)
        return HStack(spacing: 8) {
            trainKey
            ForEach(fit.visible, id: \.persistentModelID) { exercise in
                sportKey(exercise)
            }
            if !fit.hidden.isEmpty {
                moreKey(count: fit.hidden.count)
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
        .padding(12)
    }

    /// A morphing key's chrome — the ONLY thing the morph moves. The id
    /// pairs it with the panel that grows out of it.
    private func keyChrome(id: String) -> some View {
        RoundedRectangle(cornerRadius: Theme.keyRadius)
            .fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
            .matchedGeometryEffect(id: id, in: morph)
    }

    /// The scratch session: walk in, start logging, keep the result as a
    /// routine at the finish if it earned it (#239). "Train" is the
    /// imperative for the workout that isn't one sport — the voice's own
    /// verb — and the dashed square is the build-as-you-go glyph the
    /// empty-workout path has always worn.
    private var trainKey: some View {
        Button { open(.train) } label: {
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
            .background(keyChrome(id: "key-train"))
        }
        .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: Theme.keyRadius, travel: 3))
        .accessibilityLabel("Train, build the workout as you go")
        .accessibilityIdentifier("quickStartTrain")
    }

    private func sportKey(_ exercise: Exercise) -> some View {
        Button { open(.sport(exercise.name)) } label: {
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
            .background(keyChrome(id: "key-\(exercise.name)"))
        }
        .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: Theme.keyRadius, travel: 3))
        .accessibilityIdentifier("quickStart-\(exercise.name)")
    }

    /// The overflow: key chrome in secondary ink (a continuation, not a
    /// sport). It morphs into the more panel, where every hidden sport
    /// sits one tap deeper — nothing becomes unreachable by not fitting.
    private func moreKey(count: Int) -> some View {
        Button { open(.more) } label: {
            Text("\(count) more")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 42)
                .background(keyChrome(id: "key-more"))
        }
        .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: Theme.keyRadius, travel: 3))
        .accessibilityLabel("\(count) more sports")
        .accessibilityIdentifier("quickStartMore")
    }

    private var editKey: some View {
        Button(action: onEdit) {
            Image(systemName: "plus")
                .font(.system(.footnote, weight: .bold))
                // Creation is green (#202) — this key edits the row,
                // it does not start a workout. No morph: it opens the
                // picker sheet (see the header note).
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14)
                .frame(minHeight: 42)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius)
                    .strokeBorder(Theme.accent.opacity(0.5)))
        }
        .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: Theme.keyRadius, travel: 3))
        .accessibilityLabel("Pick which workouts appear here")
        .accessibilityIdentifier("quickStartEditButton")
    }

    // MARK: - Panels

    /// A panel's shared chrome: the key's rounded rect grown to the
    /// card's own radius, flush with the card's edge, drawn OVER the
    /// dashed shell. zIndex keeps it above the outgoing rack mid-morph.
    private func panel<Content: View>(sourceID: String, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.borderStrong))
                    .matchedGeometryEffect(id: sourceID, in: morph)
            )
            .zIndex(1)
            .transition(.opacity)
    }

    /// The way home: an icon-only r11 raised key (the icon-key law), the
    /// left chevron because the morph is navigation within the card.
    private var backKey: some View {
        Button { open(.rack) } label: {
            Image(systemName: "chevron.left")
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34, height: 34)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: Theme.keyRadius, travel: 3))
        .accessibilityLabel("Back")
        .accessibilityIdentifier("anytimeBack")
    }

    private func panelHeader(_ title: String) -> some View {
        HStack(spacing: 9) {
            backKey
            Text(title)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private func sportPanel(_ exercise: Exercise) -> some View {
        let presets = QuickStartPresets.presets(for: exercise)
        return VStack(alignment: .leading, spacing: 0) {
            panelHeader(label(for: exercise))
            if let line = lastOuting(exercise) {
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 8)
            }
            if !presets.isEmpty {
                FlowLayout(spacing: 6) {
                    SelectableChip(label: "Open", isSelected: pickedPreset == nil, identifier: "anytimePreset-open") {
                        pickedPreset = nil
                    }
                    ForEach(presets, id: \.label) { preset in
                        SelectableChip(label: preset.label, isSelected: pickedPreset == preset, identifier: "anytimePreset-\(preset.label)") {
                            pickedPreset = preset
                        }
                    }
                    // The ellipsis convention: opens more UI. The sheet
                    // owns the triad law; the chips never grow wheels.
                    SelectableChip(label: "Custom…", isSelected: false, identifier: "anytimeCustom") {
                        open(.rack)
                        onCustom(exercise)
                    }
                }
                .padding(.top, 10)
            }
            StartFlashButton(label: "Start", identifier: "anytimeStart") {
                commitSportStart(exercise)
            }
            .padding(.top, 12)
        }
    }

    private var trainPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader("Train")
            Text("Starts empty. Build as you go.")
                .font(.system(.footnote))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 8)
            StartFlashButton(label: "Start empty", identifier: "anytimeStartEmpty") {
                onStartEmpty()
            }
            .padding(.top, 12)
            QuietKey(label: "Pick a routine", identifier: "anytimeChooseRoutine") {
                open(.rack)
                onChooseRoutine()
            }
            .padding(.top, 8)
        }
    }

    /// Every sport the rack couldn't fit, one level deeper — each key
    /// morphs on into its own config panel (the ids pair panel-to-panel
    /// exactly as they pair rack-to-panel).
    private var morePanel: some View {
        let hidden = fitting(width: containerWidth).hidden
        return VStack(alignment: .leading, spacing: 0) {
            panelHeader("More sports")
            FlowLayout(spacing: 8) {
                ForEach(hidden, id: \.persistentModelID) { exercise in
                    sportKey(exercise)
                }
            }
            .padding(.top, 10)
        }
    }

    private func commitSportStart(_ exercise: Exercise) {
        let config = SessionExerciseConfig(exercise: exercise)
        // The chip's word is the whole prescription: clear the prefilled
        // triad, then write the one target the chip names. Open writes
        // nothing — an untargeted effort gets the count-up clock.
        for metric in CardioTargets.triad {
            config.setTarget(metric, to: nil)
        }
        if let preset = pickedPreset {
            config.setTarget(preset.metric, to: preset.value)
        }
        onStart(config)
    }

    // MARK: - Labels & fitting

    /// The key's imperative — unless two picks resolve to the same verb
    /// (both climbers, a custom bike beside Cycling), where the colliding
    /// keys fall back to their own names: two keys both saying "Ride"
    /// is a coin flip, and a noun beats a coin flip.
    private func label(for exercise: Exercise) -> String {
        let mine = QuickStartLabel.text(for: exercise)
        let twins = exercises.filter { QuickStartLabel.text(for: $0) == mine }
        return twins.count > 1 ? exercise.name : mine
    }

    /// Greedy left-to-right fit, reserving the Train and edit keys always
    /// and the "N more" key whenever anything is left over. At least one
    /// sport key always shows — one real key plus "N more" beats only
    /// chrome. Width available to keys: the container minus the rack's
    /// own 12 pt pads.
    private func fitting(width: CGFloat) -> (visible: [Exercise], hidden: [Exercise]) {
        guard width > 0, exercises.count > 1 else { return (exercises, []) }
        let spacing: CGFloat = 8
        let widths = exercises.map { Self.keyWidth(label(for: $0), hasGlyph: true) }
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
        // overestimating is the safe side: a key drops into "N more" one
        // width early instead of truncating mid-label.
        if hasGlyph { width += font.pointSize * 1.6 + 7 }
        return width + 28 + 2
    }

    /// The green "+" cap: a bold footnote glyph between 14 pt pads.
    private static var editKeyWidth: CGFloat {
        UIFont.preferredFont(forTextStyle: .footnote).pointSize * 1.2 + 28 + 2
    }
}

/// Preset targets for the anytime sport panels: round numbers in the
/// profile's OWN unit, never conversions — a "5K" chip on a miles
/// profile would start writing 3.107, which is nobody's prescription.
/// Distance chips write `.distance`, minute chips `.duration`; the
/// triad's third value stays derived, exactly as the sheets keep it.
enum QuickStartPresets {
    struct Preset: Equatable {
        let label: String
        let metric: WorkoutMetric
        let value: Double
    }

    static func presets(for exercise: Exercise) -> [Preset] {
        let profile = exercise.metricProfile
        guard CardioTargets.applies(to: profile) else { return [] }
        switch exercise.modality {
        case .running:
            return runDistances(profile.distanceUnit) + [minutes(30)]
        case .walking, .hiking:
            return [minutes(30), minutes(60)]
        case .cycling:
            return rideDistances(profile.distanceUnit) + [minutes(45)]
        case .rowing:
            return rowDistances(profile.distanceUnit) + [minutes(20)]
        case .swimming:
            return swimDistances(profile.distanceUnit) + [minutes(30)]
        case .jumpRope, .stairClimbing, .elliptical, .cardio:
            return [minutes(15), minutes(30)]
        case .strength, .flexibility:
            return []
        }
    }

    private static func minutes(_ count: Int) -> Preset {
        Preset(label: "\(count) min", metric: .duration, value: Double(count * 60))
    }

    private static func distance(_ value: Double, _ label: String) -> Preset {
        Preset(label: label, metric: .distance, value: value)
    }

    private static func runDistances(_ unit: DistanceUnit) -> [Preset] {
        switch unit {
        case .kilometers: [distance(5, "5K"), distance(10, "10K")]
        case .miles: [distance(3, "3 mi"), distance(6, "6 mi")]
        case .meters: [distance(5000, "5,000 m")]
        case .yards: []
        }
    }

    private static func rideDistances(_ unit: DistanceUnit) -> [Preset] {
        switch unit {
        case .kilometers: [distance(20, "20K"), distance(40, "40K")]
        case .miles: [distance(10, "10 mi"), distance(25, "25 mi")]
        case .meters, .yards: []
        }
    }

    private static func rowDistances(_ unit: DistanceUnit) -> [Preset] {
        switch unit {
        case .meters: [distance(2000, "2,000 m"), distance(5000, "5,000 m")]
        case .kilometers: [distance(2, "2K"), distance(5, "5K")]
        case .miles, .yards: []
        }
    }

    private static func swimDistances(_ unit: DistanceUnit) -> [Preset] {
        switch unit {
        case .yards: [distance(1000, "1,000 yd"), distance(1500, "1,500 yd")]
        case .meters: [distance(1000, "1,000 m"), distance(1500, "1,500 m")]
        case .kilometers, .miles: []
        }
    }
}
