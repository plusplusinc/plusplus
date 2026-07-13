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
    @State private var draft: ExerciseDraft
    @State private var defaultsWheel: WorkoutMetric?
    @State private var showingDefaultRepsWheel = false

    init(editing exercise: Exercise? = nil) {
        editingExercise = exercise
        _draft = State(initialValue: exercise.map(ExerciseDraft.init(from:)) ?? ExerciseDraft())
    }

    /// New custom exercise with the name pre-filled (the Library's
    /// "Create “query”" path, #63).
    init(prefillName: String) {
        editingExercise = nil
        let draft = ExerciseDraft()
        draft.name = prefillName
        _draft = State(initialValue: draft)
    }

    /// New custom exercise with gear pre-attached — the equipment
    /// screen's "add an exercise with this" path (#137). The gear's
    /// suggested profile arrives with it (a rower exercise starts with
    /// the rower's metrics).
    init(prefillEquipment: Equipment) {
        editingExercise = nil
        let draft = ExerciseDraft()
        draft.selectedEquipment = [prefillEquipment]
        draft.adoptSuggestedProfile(
            SeedData.suggestedProfile(type: .weightReps, equipment: [prefillEquipment])
        )
        _draft = State(initialValue: draft)
    }

    private var isBuiltIn: Bool { editingExercise?.isBuiltIn == true }

    /// The catalog's profile for the built-in being edited.
    private var builtInDefaultProfile: MetricProfile? {
        guard isBuiltIn else { return nil }
        return SeedData.builtInProfile(named: editingExercise?.name ?? "")
    }

    /// Anything off the canonical definition counts as customized —
    /// built-ins ship with no notes or video, so their presence alone
    /// is a customization.
    private var differsFromDefault: Bool {
        guard isBuiltIn, let def = SeedData.builtInDefinition(named: editingExercise?.name ?? "") else { return false }
        return draft.muscleGroup != def.muscleGroup
            || draft.metricProfile != (builtInDefaultProfile ?? .derived(from: def.exerciseType))
            || Set(draft.selectedEquipment.map(\.name)) != Set(def.equipmentNames)
            || !draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.videoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var existingNames: [String] {
        allExercises.map(\.name)
    }

    private var canSave: Bool {
        draft.canSave(existingNames: existingNames, editedName: editingExercise?.name)
    }

    private var selectedEquipmentSorted: [Equipment] {
        draft.selectedEquipment.sorted { $0.name < $1.name }
    }

    private var unselectedEquipment: [Equipment] {
        allEquipment.filter { !draft.selectedEquipment.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: editingExercise == nil ? "New exercise" : "Edit exercise",
                subtitle: editingExercise?.name,
                actionLabel: "Save",
                actionEnabled: canSave,
                actionIdentifier: "saveExerciseButton",
                onCancel: { dismiss() },
                action: { save() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SheetSectionLabel("NAME")
                        .padding(.top, 24)
                    TextField("Exercise name", text: $draft.name)
                        .font(.system(.body))
                        .foregroundStyle(isBuiltIn ? Theme.textSecondary : Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
                        .disabled(isBuiltIn)
                        .accessibilityIdentifier("exerciseNameField")
                    if isBuiltIn {
                        Text("Built-in names are fixed — history and sync key on them. Create a custom exercise for a different name.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 6)
                    }
                    if draft.isDuplicate(among: existingNames, excluding: editingExercise?.name) {
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 7)], spacing: 7) {
                        ForEach(WorkoutMetric.allCases.filter { $0 != .rest }) { metric in
                            metricChip(metric)
                        }
                    }
                    if !draft.metricProfile.isValid {
                        Text("Track at least one of reps, duration, distance, or calories — something has to say what a set is.")
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
                        SegmentedTabs(
                            options: DistanceUnit.allCases.map(\.symbol),
                            selectedIndex: Binding(
                                get: { DistanceUnit.allCases.firstIndex(of: draft.distanceUnit) ?? 0 },
                                set: { draft.distanceUnit = DistanceUnit.allCases[$0] }
                            )
                        )
                        Text("A declaration, not a conversion — numbers keep their value if you change it. Pace follows: \(draft.distanceUnit.paceLabel).")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 6)
                    }

                    SheetSectionLabel("DEFAULTS")
                        .padding(.top, 24)
                    defaultsCard
                    HStack {
                        Text("Optional — new routine entries start from these. Routine edits keep them current.")
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

                    SheetSectionLabel("MUSCLE GROUP")
                        .padding(.top, 24)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 7)], spacing: 7) {
                        ForEach(MuscleGroup.allCases) { group in
                            muscleChip(group)
                        }
                    }

                    SheetSectionLabel("REQUIRES")
                        .padding(.top, 24)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 7)], spacing: 7) {
                        ForEach(selectedEquipmentSorted) { equipment in
                            equipmentChip(equipment)
                        }
                        addEquipmentChip
                    }
                    Text(draft.selectedEquipment.isEmpty
                         ? "Bodyweight — no equipment required."
                         : "Needs all of these.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 6)

                    SheetSectionLabel("NOTES")
                        .padding(.top, 24)
                    TextField("Form cues, tempo…", text: $draft.notes, axis: .vertical)
                        .font(.system(.footnote))
                        .lineLimit(3...8)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))

                    SheetSectionLabel("VIDEO")
                        .padding(.top, 24)
                    TextField("Link (optional)", text: $draft.videoURL)
                        .font(.system(.footnote))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
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
                        Text("Restores the catalog definition — equipment, muscle group, tracked values — and clears notes and video.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 6)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .padding(.horizontal, 18)
        .presentationBackground(Theme.surface)
        // A new exercise adopts its gear's suggested profile as the gear
        // changes — until the user touches the chips, which latches
        // their choice (ExerciseDraft.metricsTouched).
        .onChange(of: draft.selectedEquipment) { _, newEquipment in
            guard editingExercise == nil else { return }
            draft.adoptSuggestedProfile(
                SeedData.suggestedProfile(type: .weightReps, equipment: Array(newEquipment))
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
            RepTargetWheelSheet(
                target: RepTarget(lower: draft.defaultReps, upper: draft.defaultRepsUpper)
            ) { newTarget in
                draft.defaultReps = newTarget.lower
                draft.defaultRepsUpper = newTarget.upper
            }
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
                        onTapValue: { showingDefaultRepsWheel = true },
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
                        onTapValue: { defaultsWheel = metric },
                        onDecrement: { stepDefault(metric, -1) },
                        onIncrement: { stepDefault(metric, 1) }
                    )
                }
            }
        }
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    /// Smallest weight-step override among the DRAFT's selected gear, so
    /// stepping reflects the equipment being edited, not the saved state.
    private var draftWeightStep: Double? {
        draft.selectedEquipment.compactMap(\.weightStep).min()
    }

    private var defaultDurationText: String {
        guard let seconds = draft.defaultDurationSeconds else { return "—" }
        return seconds >= 60
            ? WorkoutMetric.duration.formatted(Double(seconds))
            : "\(seconds)s"
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

    /// TRACKED VALUES chip — multi-select over the curated vocabulary,
    /// solid selection blue like every selected state (#210).
    private func metricChip(_ metric: WorkoutMetric) -> some View {
        let selected = draft.isTracked(metric)
        return Button {
            draft.toggleMetric(metric)
        } label: {
            Text(metric.label)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(selected ? Theme.onSelected : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(selected ? Theme.selected : Theme.background, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.border))
        }
        .accessibilityIdentifier("metricChip-\(metric.rawValue)")
        .animation(Theme.Anim.selection, value: selected)
    }

    private func muscleChip(_ group: MuscleGroup) -> some View {
        let selected = draft.muscleGroup == group
        return Button {
            draft.muscleGroup = group
        } label: {
            // Solid selection blue (#210) — this was the stray CREAM
            // on-state; ink fills are for actions, blue is selection.
            Text(group.displayName)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(selected ? Theme.onSelected : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(selected ? Theme.selected : Theme.background, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.border))
        }
        .animation(Theme.Anim.selection, value: selected)
    }

    private func equipmentChip(_ equipment: Equipment) -> some View {
        Button {
            draft.selectedEquipment.remove(equipment)
        } label: {
            HStack(spacing: 5) {
                Text(equipment.name)
                    .font(.system(.footnote, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Image(systemName: "xmark")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Theme.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.borderStrong))
        }
        .accessibilityLabel("Remove \(equipment.name)")
    }

    private var addEquipmentChip: some View {
        Menu {
            ForEach(unselectedEquipment) { equipment in
                Button(equipment.name) {
                    draft.selectedEquipment.insert(equipment)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text("+")
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Add")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .overlay(Capsule().strokeBorder(Theme.borderStrong))
        }
        .disabled(unselectedEquipment.isEmpty)
    }

    private func revertToDefault() {
        guard let def = SeedData.builtInDefinition(named: editingExercise?.name ?? "") else { return }
        draft.muscleGroup = def.muscleGroup
        draft.setProfile(builtInDefaultProfile ?? .derived(from: def.exerciseType))
        draft.selectedEquipment = Set(allEquipment.filter { def.equipmentNames.contains($0.name) })
        draft.notes = ""
        draft.videoURL = ""
    }

    private func save() {
        if let exercise = editingExercise {
            draft.apply(to: exercise)
        } else {
            let exercise = Exercise(name: draft.trimmedName, muscleGroup: draft.muscleGroup)
            modelContext.insert(exercise)
            draft.apply(to: exercise)
        }
        dismiss()
    }
}

/// Read-only exercise details: muscle group, equipment, notes, video link.
/// Reachable from the routine detail screen so form cues are available
/// mid-routine.
struct ExerciseInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Muscle Group", value: exercise.muscleGroup.displayName)
                    LabeledContent(
                        "Equipment",
                        value: exercise.equipment.isEmpty
                            ? "Bodyweight"
                            : exercise.equipment.map(\.name).sorted().joined(separator: ", ")
                    )
                }

                if let notes = exercise.notes {
                    Section("Notes") {
                        Text(notes)
                    }
                }

                if let videoURL = exercise.videoURL, let url = URL(string: videoURL) {
                    Section {
                        Link(destination: url) {
                            Label("Watch video", systemImage: "play.rectangle")
                        }
                    }
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
