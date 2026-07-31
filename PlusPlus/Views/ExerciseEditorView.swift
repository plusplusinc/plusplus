import SwiftUI
import SwiftData
import PlusPlusKit

/// Create or edit an exercise, in the v2 sheet language (#86): terse
/// sections, chips for muscle group, and equipment presented as
/// explicit "requires all of these" chips. Built-ins are editable too
/// (#136) — everything but the name, which history and sync key on —
/// and revert to their canonical catalog definition.
struct ExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query private var allExercises: [Exercise]

    private let editingExercise: Exercise?
    /// Fired with the freshly CREATED exercise (create path only) so a
    /// caller can route it onward — the routine picker adds it straight to
    /// the routine and pops back, instead of returning to the picker.
    private let onCreated: ((Exercise) -> Void)?
    @State private var draft: ExerciseDraft
    @State private var defaultsWheel: WorkoutMetric?
    @State private var showingDefaultRepsWheel = false
    /// The draft as it opened — the discard guard's baseline (design
    /// review 2026-07-23: this is the app's biggest form, the one place
    /// Cancel-is-instant cost real typing; Dave's call to confirm).
    @State private var initialFingerprint: [String]
    @State private var confirmingDiscard = false
    /// The name this editor just wrote, held from `save()` until the sheet
    /// is actually gone. Dismissal is animated, so the body renders more
    /// frames AFTER the insert — by which point `allExercises` carries the
    /// row we just made, and the name field compares the draft to it: the
    /// duplicate warning flashes red under the field and Save dims, on the
    /// way out. A rename does the same, since its exclusion is the OLD
    /// name and the newly written one is not it.
    @State private var savedName: String?
    /// Which of the form's three fields holds the keyboard. Every way OUT of
    /// the keyboard clears this: Return, a scroll, a tap on the form's ground,
    /// and anything that opens a screen over the form (a pick-list push, a
    /// defaults wheel, the discard dialog).
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, notes, video
    }

    init(editing exercise: Exercise) {
        editingExercise = exercise
        onCreated = nil
        let draft = ExerciseDraft(from: exercise)
        _draft = State(initialValue: draft)
        _initialFingerprint = State(initialValue: draft.fingerprint)
    }

    /// New custom exercise seeded from wherever creation started: the
    /// search query as the name (the "Create “query”" path, #63), the
    /// filtered muscle group, and gear — from an active equipment
    /// filter or the equipment screen's "add an exercise with this"
    /// path (#137). Gear brings its suggested profile (a rower
    /// exercise starts with the rower's metrics); everything is an
    /// editable starting point, not a commitment.
    init(prefillName: String = "", prefillMuscleGroup: MuscleGroup? = nil, prefillEquipment: Set<Equipment> = [], onCreated: ((Exercise) -> Void)? = nil) {
        editingExercise = nil
        self.onCreated = onCreated
        let draft = ExerciseDraft()
        draft.name = prefillName
        if let prefillMuscleGroup {
            draft.muscleGroups = [prefillMuscleGroup]
        }
        if !prefillEquipment.isEmpty {
            draft.selectedEquipment = prefillEquipment
            // Sorted, not Array(set): the merge is order-sensitive
            // (first distance-carrying profile wins the unit), and an
            // unstable order would flip the suggestion run to run.
            draft.adoptSuggestedProfile(
                SeedData.suggestedProfile(type: .weightReps, equipment: prefillEquipment.sorted { $0.name < $1.name })
            )
        }
        _draft = State(initialValue: draft)
        // Prefills are the baseline, not edits — dismissing an untouched
        // prefilled sheet stays instant.
        _initialFingerprint = State(initialValue: draft.fingerprint)
    }

    private var isBuiltIn: Bool { editingExercise?.isBuiltIn == true }

    /// The catalog's profile for the built-in being edited.
    private var builtInDefaultProfile: MetricProfile? {
        guard isBuiltIn else { return nil }
        return SeedData.builtInProfile(named: editingExercise?.name ?? "")
    }

    /// Names what the chips ARE, since they now show only what's picked.
    private var muscleGroupCaption: String {
        draft.muscleGroups.count > 1
            ? "Every group this works. \(draft.muscleGroup.displayName) leads."
            : "Every group this works."
    }

    /// The pushed list's footer. With one group left it carries the rule
    /// its disabled row can't state; with more, which one leads.
    private var muscleGroupPickNote: String {
        draft.muscleGroups.count > 1
            ? "\(draft.muscleGroup.displayName) leads."
            : "Keep at least one."
    }

    /// Anything off the canonical definition counts as customized —
    /// built-ins ship with no notes or video, so their presence alone
    /// is a customization.
    private var differsFromDefault: Bool {
        guard isBuiltIn, let def = SeedData.builtInDefinition(named: editingExercise?.name ?? "") else { return false }
        return draft.muscleGroups != def.muscleGroups
            || draft.metricProfile != (builtInDefaultProfile ?? .derived(from: def.exerciseType))
            || Set(draft.selectedEquipment.map(\.name)) != Set(def.equipmentNames)
            || !draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.videoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var existingNames: [String] {
        allExercises.map(\.name)
    }

    /// The name a collision is allowed to be — an exercise never counts as
    /// its own duplicate, whether it is the one being edited or the one
    /// this editor just saved.
    private var excludedName: String? {
        savedName ?? editingExercise?.name
    }

    private var canSave: Bool {
        draft.canSave(existingNames: existingNames, editedName: excludedName)
    }

    /// Whether dismissing now would cost real input.
    private var isDirty: Bool {
        draft.fingerprint != initialFingerprint
    }

    private var selectedEquipmentSorted: [Equipment] {
        draft.selectedEquipment.sorted { $0.name < $1.name }
    }

    var body: some View {
        // Self-contained NavigationStack so the two "+ Add" rows can PUSH
        // their pick lists (the ScheduleTray / Voice-cues pattern): the
        // root bar is hidden so SheetHeader stays the header, and only the
        // pushed list wears a system bar — which is what buys the back
        // swipe, the titled back button and the standard slide.
        NavigationStack {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: editingExercise == nil ? "New exercise" : "Edit exercise",
                subtitle: editingExercise?.name,
                actionLabel: "Save",
                actionEnabled: canSave,
                actionIdentifier: "saveExerciseButton",
                onCancel: {
                    // Dirty drafts confirm (Dave, 2026-07-23) — the one
                    // deliberate exception to Cancel-is-instant, matched
                    // by the blocked swipe below (the Mail-compose
                    // pattern). A clean sheet still closes instantly.
                    // The keyboard goes first either way, so the discard
                    // dialog doesn't arrive on top of it.
                    focusedField = nil
                    if isDirty {
                        confirmingDiscard = true
                    } else {
                        dismiss()
                    }
                },
                action: { save() }
            )
            .padding(.horizontal, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SheetSectionLabel("NAME")
                        .padding(.top, 24)
                    TextField("Exercise name", text: $draft.name)
                        .font(.system(.body))
                        .foregroundStyle(isBuiltIn ? Theme.textSecondary : Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
                        .disabled(isBuiltIn)
                        .focused($focusedField, equals: .name)
                        // Return puts the keyboard away. It does NOT save —
                        // Return never commits or navigates in this app.
                        .submitLabel(.done)
                        .accessibilityIdentifier("exerciseNameField")
                    if isBuiltIn {
                        Text("Built-in names are fixed. History and sync key on them. Create a custom exercise for a different name.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 6)
                    }
                    if draft.isDuplicate(among: existingNames, excluding: excludedName) {
                        Text("An exercise with this name already exists.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.destructive)
                            .padding(.top, 6)
                    } else if draft.isRename(of: editingExercise?.name) {
                        Text("Renaming starts a fresh exercise: past sets and \"last time\" stay with \"\(editingExercise?.name ?? "")\".")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.notes)
                            .padding(.top, 6)
                    }

                    SheetSectionLabel("TRACKED VALUES")
                        .padding(.top, 24)
                    // The shared chip family in the shared wrap layout — the
                    // editor's chips forked as capsules pre-2026-07-20 and were
                    // folded back in with the design-review round.
                    FlowLayout(horizontalSpacing: 16, verticalSpacing: 8) {
                        ForEach(WorkoutMetric.allCases.filter { !$0.isBlockConfiguration }) { metric in
                            SelectableChip(
                                label: metric.label,
                                isSelected: draft.isTracked(metric),
                                identifier: "metricChip-\(metric.rawValue)"
                            ) {
                                draft.toggleMetric(metric)
                            }
                        }
                    }
                    if !draft.metricProfile.isValid {
                        Text("Track at least one of reps, duration, distance, or calories. Something has to say what a set is.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.destructive)
                            .padding(.top, 6)
                    } else {
                        Text("What the planning sheet and set screen show for this exercise.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 6)
                    }

                    if draft.usesDistanceUnit {
                        SheetSectionLabel("DISTANCE UNIT")
                            .padding(.top, 24)
                        Picker("Distance unit", selection: $draft.distanceUnit) {
                            ForEach(DistanceUnit.allCases, id: \.self) { unit in
                                Text(unit.symbol).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .tint(Theme.selected)
                        Text("A declaration, not a conversion. Numbers keep their value if you change it. Pace follows: \(draft.distanceUnit.paceLabel).")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 6)
                    }

                    // Outdoor lives with the distance vocabulary: it only
                    // means something with a distance or pace metric to
                    // feed (#378), and the flag itself is a flat control —
                    // toggles stay flat per the press grammar.
                    if draft.canBeOutdoor {
                        SheetSectionLabel("OUTDOOR")
                            .padding(.top, 24)
                        Toggle(isOn: Binding(
                            get: { draft.isOutdoor },
                            set: { draft.setOutdoor($0) }   // latches — prefill must never revert it
                        )) {
                            Text("Outdoor (GPS)")
                                .font(.system(.subheadline, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .tint(Theme.selected)
                        .accessibilityIdentifier("outdoorToggle")
                        Text("Live pace and distance from GPS while you work out, and the route on the record.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 6)
                    }

                    SheetSectionLabel("DEFAULTS")
                        .padding(.top, 24)
                    defaultsCard
                    HStack {
                        Text("Optional. New routine entries start from these. Routine edits keep them current.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                        if draft.hasDefaultTargets {
                            Spacer()
                            Button("Clear") {
                                draft.clearDefaultTargets()
                            }
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityIdentifier("clearDefaultsButton")
                        }
                    }
                    .padding(.top, 6)

                    // MUSCLE GROUPS, plural and multi-select: most moves
                    // work several, and picking one used to mean the rest
                    // went unsaid — a bench press was chest and its triceps
                    // existed nowhere. The FIRST one picked is the primary
                    // (it leads the chips and the capsules, and it is what
                    // single-group readers see), which is why the chips keep
                    // selection order rather than re-sorting.
                    //
                    // Eleven always-visible chips read as a wall (Dave), so
                    // this section is the same shape as REQUIRES below it:
                    // what you PICKED, plus one key that pushes the full
                    // list. Two adjacent multi-selects behaving differently
                    // was the actual problem.
                    SheetSectionLabel("MUSCLE GROUPS")
                        .padding(.top, 24)
                    FlowLayout(horizontalSpacing: 16, verticalSpacing: 8) {
                        ForEach(draft.muscleGroups) { group in
                            muscleGroupChip(group)
                        }
                        addChip(title: "Muscle groups", identifier: "addMuscleGroupButton") {
                            muscleGroupPickList()
                        }
                    }
                    Text(muscleGroupCaption)
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 6)

                    SheetSectionLabel("REQUIRES")
                        .padding(.top, 24)
                    FlowLayout(horizontalSpacing: 16, verticalSpacing: 8) {
                        ForEach(selectedEquipmentSorted) { equipment in
                            equipmentChip(equipment)
                        }
                        addChip(title: "Equipment", identifier: "addEquipmentButton") {
                            equipmentPickList()
                        }
                    }
                    Text(draft.selectedEquipment.isEmpty
                         ? "Bodyweight. No equipment required."
                         : "Needs all of these.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 6)

                    SheetSectionLabel("NOTES")
                        .padding(.top, 24)
                    TextField("Form cues, tempo…", text: $draft.notes, axis: .vertical)
                        .font(.system(.footnote))
                        .focused($focusedField, equals: .notes)
                        .lineLimit(3...8)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))

                    SheetSectionLabel("VIDEO")
                        .padding(.top, 24)
                    TextField("Link (optional)", text: $draft.videoURL)
                        .font(.system(.footnote))
                        .focused($focusedField, equals: .video)
                        .submitLabel(.done)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
                    if draft.normalizedVideoURL == .invalid {
                        Text("That doesn't look like a valid link.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.destructive)
                            .padding(.top, 6)
                    }

                    if differsFromDefault {
                        SheetActionButton("Revert to default", systemImage: "arrow.counterclockwise") {
                            revertToDefault()
                        }
                        .padding(.top, 20)
                        Text("Restores the catalog definition (equipment, muscle group, tracked values) and clears notes and video.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
                // The form's whole width, so the ground below reaches the
                // margins beside a chip and not just the content column.
                .frame(maxWidth: .infinity, alignment: .leading)
                // Tapping the form's GROUND puts the keyboard away. It is a
                // layer BEHIND the form, deliberately, rather than an
                // `.onTapGesture` on the content stack: behind, it can only
                // ever receive a touch no control in front of it took, so
                // the chips still toggle and — the case that matters — the
                // three fields still take their own focus tap. An ancestor
                // gesture races the text field for that tap, and losing that
                // race means the keyboard blinks shut on the way IN, which
                // is a worse bug than the one being fixed. Taps are not
                // pans, so nothing here claims the scroll
                // (ui-interaction.md's claim-vs-does law is about drags).
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { focusedField = nil }
                )
            }
            // The keyboard's other exit, and the one this form was missing
            // entirely: scrolling. Every other scrolling surface in the app
            // that holds a field already declares it — this is the biggest
            // form in the app and the keyboard covers half of it, so with no
            // scroll dismissal and no ground to tap, the name field kept the
            // keyboard until the sheet closed.
            .scrollDismissesKeyboard(.immediately)
        }
        // A new exercise adopts its gear's suggested profile as the gear
        // changes — until the user touches the chips, which latches
        // their choice (ExerciseDraft.metricsTouched).
        .onChange(of: draft.selectedEquipment) { _, newEquipment in
            guard editingExercise == nil else { return }
            // Sorted for a stable merge — see the prefill init.
            draft.adoptSuggestedProfile(
                SeedData.suggestedProfile(type: .weightReps, equipment: newEquipment.sorted { $0.name < $1.name })
            )
        }
        .sheet(item: $defaultsWheel) { metric in
            MetricWheelSheet(
                metric: metric,
                weightUnit: weightUnit,
                distanceUnit: draft.distanceUnit,
                value: Binding(
                    get: { draft.defaultTarget(metric) },
                    set: { draft.setDefaultTarget(metric, to: $0) }
                )
            )
        }
        .sheet(isPresented: $showingDefaultRepsWheel) {
            RepTargetSheet(
                target: RepTarget(lower: draft.defaultReps, upper: draft.defaultRepsUpper)
            ) { newTarget in
                draft.defaultReps = newTarget.lower
                draft.defaultRepsUpper = newTarget.upper
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        }
        // Presentation-level modifiers sit OUTSIDE the NavigationStack, so
        // they address the sheet itself rather than its root screen.
        // `background`, not `surface`: the trays agreed on one elevation
        // (#462).
        .presentationBackground(Theme.background)
        // A dirty draft can't be swiped away silently — the swipe bounces
        // (standard compose behavior) and Cancel carries the confirm.
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    // MARK: - Defaults (#187)

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

    /// The same stepper card the routine planning sheet uses, writing to
    /// the draft. One row per TRACKED metric — the chips above decide.
    private var defaultsCard: some View {
        VStack(spacing: 0) {
            ForEach(draft.metricProfile.metrics) { metric in
                if metric == .reps {
                    MetricStepperRow(
                        label: "Reps",
                        value: RepTarget(lower: draft.defaultReps, upper: draft.defaultRepsUpper).display,
                        identifier: "defaultReps",
                        // Same rule as the pushes: a wheel must not open
                        // under a keyboard the form left standing.
                        onTapValue: {
                            focusedField = nil
                            showingDefaultRepsWheel = true
                        },
                        onDecrement: { applyDefaultReps(RepTarget(lower: draft.defaultReps, upper: draft.defaultRepsUpper).decremented()) },
                        onIncrement: { applyDefaultReps(RepTarget(lower: draft.defaultReps, upper: draft.defaultRepsUpper).incremented()) }
                    )
                } else {
                    MetricStepperRow(
                        label: metric.label,
                        value: metric == .duration
                            ? defaultDurationText
                            : metric.displayText(draft.defaultTarget(metric), weightUnit: weightUnit, distanceUnit: draft.distanceUnit),
                        identifier: "default-\(metric.rawValue)",
                        onTapValue: {
                            focusedField = nil
                            defaultsWheel = metric
                        },
                        onDecrement: { stepDefault(metric, -1) },
                        onIncrement: { stepDefault(metric, 1) }
                    )
                }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    /// Smallest weight-step override among the DRAFT's selected gear, so
    /// stepping reflects the equipment being edited, not the saved state.
    private var draftWeightStep: Double? {
        draft.selectedEquipment.compactMap(\.weightStep).min()
    }

    private var defaultDurationText: String {
        guard let seconds = draft.defaultDurationSeconds else { return "—" }
        return DurationTape.label(for: seconds)
    }

    private func stepDefault(_ metric: WorkoutMetric, _ direction: Double) {
        let stepOverride = metric == .weight ? draftWeightStep : nil
        let current = draft.defaultTarget(metric)
        let stepped = direction > 0
            ? metric.incremented(current, weightUnit: weightUnit, distanceUnit: draft.distanceUnit, stepOverride: stepOverride)
            : metric.decremented(current, weightUnit: weightUnit, distanceUnit: draft.distanceUnit, stepOverride: stepOverride)
        draft.setDefaultTarget(metric, to: stepped)
    }

    private func applyDefaultReps(_ target: RepTarget) {
        draft.defaultReps = target.lower
        draft.defaultRepsUpper = target.upper
    }

    /// REQUIRES chip — a removable tag, so it wears the r11 control shape
    /// (it's a button: tapping removes), sized to its content like every
    /// chip in the family. Metrics mirror SelectableChip's so the section
    /// reads as one vocabulary.
    private func equipmentChip(_ equipment: Equipment) -> some View {
        Button {
            draft.selectedEquipment.remove(equipment)
        } label: {
            HStack(spacing: 5) {
                Text(equipment.name)
                    .font(.system(.footnote, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius)
                .strokeBorder(Theme.borderStrong, lineWidth: 1))
            // Vertical-only hit target, flush like SelectableChip (2026-07-24).
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Remove \(equipment.name)")
    }

    /// MUSCLE GROUPS chip — the equipment chip's twin, so the editor's two
    /// multi-selects read as one thing. Tapping removes, except when it is
    /// the last one left: that chip is DISABLED and drops its ✕ rather than
    /// swallowing the tap, since a control that looks live and does nothing
    /// is the dead-tap class (build 76).
    private func muscleGroupChip(_ group: MuscleGroup) -> some View {
        let isLast = draft.muscleGroups.count == 1
        return Button {
            withAnimation(Theme.Anim.selection) {
                draft.toggleMuscleGroup(group)
            }
        } label: {
            HStack(spacing: 5) {
                Text(group.displayName)
                    .font(.system(.footnote, weight: .semibold))
                    .lineLimit(1)
                if !isLast {
                    Image(systemName: "xmark")
                        .font(.system(.caption2, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius)
                .strokeBorder(Theme.borderStrong, lineWidth: 1))
            // Vertical-only hit target, flush like SelectableChip (2026-07-24).
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .disabled(isLast)
        .accessibilityLabel(isLast ? group.displayName : "Remove \(group.displayName)")
    }

    /// The one "open the list" key, shared by both sections. A
    /// `NavigationLink`, so the push is the system's.
    private func addChip<Destination: View>(
        title: String,
        identifier: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            // A push while focused must not strand the keyboard (#213) — the
            // pick list would arrive with the editor's keyboard still up over
            // it. On the destination, not a gesture on the link: a
            // simultaneous tap layered on a NavigationLink is the kind of
            // thing that eats the activation.
            destination()
                .onAppear { focusedField = nil }
        } label: {
            HStack(spacing: 5) {
                Text("+")
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Add")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .overlay(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius)
                .strokeBorder(Theme.borderStrong, lineWidth: 1))
            // Vertical-only hit target, flush like SelectableChip (2026-07-24).
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(title.lowercased())")
        .accessibilityIdentifier(identifier)
    }

    /// Flat and alphabetical, searched rather than grouped — the
    /// presented-catalog law (2026-07-25), and the only sane shape for a
    /// hundred rows. Selection toggles IN the list, so adding four pieces
    /// of equipment is four taps, not four trips.
    @ViewBuilder
    private func equipmentPickList() -> some View {
        SheetPickList(
            title: "Equipment",
            sections: [SheetPickList.Section(
                title: nil,
                options: allEquipment.map { SheetPickList.Option(id: $0.name, name: $0.name) }
            )],
            selected: Set(draft.selectedEquipment.map(\.name)),
            searchPrompt: "Search equipment",
            searchIdentifier: "equipmentPickSearchField",
            note: draft.selectedEquipment.isEmpty ? "Bodyweight. No equipment required." : "Needs all of these.",
            onToggle: { name in
                guard let equipment = allEquipment.first(where: { $0.name == name }) else { return }
                if draft.selectedEquipment.contains(equipment) {
                    draft.selectedEquipment.remove(equipment)
                } else {
                    draft.selectedEquipment.insert(equipment)
                }
            }
        )
    }

    /// Eleven rows, all on screen at once, so no field — grouped by region
    /// instead (`MuscleGroup.grouped`, which had been sitting in Kit unused
    /// waiting for a surface that wanted structure).
    @ViewBuilder
    private func muscleGroupPickList() -> some View {
        SheetPickList(
            title: "Muscle groups",
            sections: MuscleGroup.grouped.map { region in
                SheetPickList.Section(
                    title: region.region.uppercased(),
                    options: region.groups.map { SheetPickList.Option(id: $0.rawValue, name: $0.displayName) }
                )
            },
            selected: Set(draft.muscleGroups.map(\.rawValue)),
            locked: draft.muscleGroups.count == 1 ? Set(draft.muscleGroups.map(\.rawValue)) : [],
            note: muscleGroupPickNote,
            onToggle: { raw in
                guard let group = MuscleGroup(rawValue: raw) else { return }
                draft.toggleMuscleGroup(group)
            }
        )
    }

    private func revertToDefault() {
        guard let def = SeedData.builtInDefinition(named: editingExercise?.name ?? "") else { return }
        draft.muscleGroups = def.muscleGroups
        draft.setProfile(builtInDefaultProfile ?? .derived(from: def.exerciseType))
        draft.selectedEquipment = Set(allEquipment.filter { def.equipmentNames.contains($0.name) })
        draft.notes = ""
        draft.videoURL = ""
    }

    private func save() {
        var created: Exercise?
        // Before the write, so no frame between the insert and the next
        // body pass can see the name without its exemption.
        savedName = draft.trimmedName
        if let exercise = editingExercise {
            draft.apply(to: exercise)
        } else {
            let exercise = Exercise(name: draft.trimmedName, muscleGroup: draft.muscleGroup)
            modelContext.insert(exercise)
            draft.apply(to: exercise)
            created = exercise
        }
        dismiss()
        // Route a freshly created exercise onward (the routine picker adds it
        // and pops back). After the editor dismisses, so the presenter is the
        // one that acts next.
        if let created { onCreated?(created) }
        // Push the saved exercise to GitHub at this boundary (debounced,
        // dirty-gated). No-op unless connected and something changed.
        GitHubSyncCoordinator.shared.requestSync(
            context: modelContext, units: WeightUnit(rawValue: weightUnitRaw) ?? .lb
        )
    }
}

// `ExerciseInfoView` was deleted 2026-07-28: a read-only exercise sheet
// (muscle group, equipment, notes, video) whose doc comment claimed the
// routine detail screen reached it, and which nothing had constructed
// since `ExerciseDetailSheet` took that job. It was also the app's last
// stock-SwiftUI surface — a plain `List` of `LabeledContent` under a
// system navigation bar with an unstyled toolbar `Done` — so it was
// carrying a button vocabulary no reachable screen used.
