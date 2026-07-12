import SwiftUI
import SwiftData
import PlusPlusKit

/// Pushed detail screens for the two catalog tabs (#137): the catalog
/// is a navigable graph, not three isolated lists. Equipment links to
/// the exercises that need it, exercises link to the routines that
/// contain them, and every dead end offers creation — chains push in
/// place with standard back navigation. Sheets survive only for
/// create/edit forms.


/// One tappable row in a catalog cross-reference block: title, mono
/// meta, chevron. Full rectangle is the hit target.
private struct CrossRefRow: View {
    let title: String
    let meta: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(meta)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Dashed create-affordance row used at the bottom of cross-ref blocks.
private struct CreateRow: View {
    let label: String
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(.caption, weight: .semibold))
                Text(label)
                    .font(.system(.footnote, weight: .semibold))
            }
            // Green content on a raised key (Quiet Arcade): creation
            // stays in the data-green voice, the key anatomy carries
            // "this commits".
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(Theme.borderStrong)
            )
        }
        .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
        .accessibilityIdentifier(identifier ?? label)
    }
}

private func crossRefBlock<Content: View>(@ViewBuilder rows: () -> Content) -> some View {
    VStack(spacing: 0) {
        rows()
    }
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
}

// MARK: - Exercise detail

struct ExerciseDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var exercise: Exercise

    @Query(sort: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt, order: .reverse)])
    private var allRoutines: [Routine]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    private var availableEquipmentNames: Set<String> {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)?.memberNames ?? []
    }

    @State private var path: PushTarget?
    @State private var showingEditor = false
    @State private var showingNewRoutine = false
    @State private var newRoutineName = ""
    @State private var showingDeleteConfirm = false
    /// A routine created from here pushes immediately — the fluid-nav
    /// promise: create it with this exercise already inside, land in it.
    @State private var createdRoutine: Routine?

    private enum PushTarget: Hashable {
        case equipment(Equipment)
        case routine(Routine)
    }

    private var usedInRoutines: [Routine] {
        allRoutines.filter { routine in
            routine.sortedGroups.flatMap(\.sortedExercises).contains { $0.exercise === exercise }
        }
    }

    /// What this exercise tracks — "Weight · Reps", "Distance · Duration
    /// · Pace · Resistance" (flexible metrics; the editor's TRACKED
    /// VALUES chips decide).
    private var typeLabel: String {
        exercise.metricProfile.metrics.map(\.label).joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(exercise.isBuiltIn ? "BUILT-IN" : "CUSTOM")
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            .foregroundStyle(exercise.isBuiltIn ? Theme.textSecondary : Theme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(exercise.isBuiltIn ? Theme.borderStrong : Theme.accent.opacity(0.4)))
                        ChipLabel(exercise.muscleGroup.displayName)
                        ChipLabel(typeLabel)
                    }

                    SheetSectionLabel("EQUIPMENT")
                        .padding(.top, 24)
                    if exercise.equipment.isEmpty {
                        Text("Bodyweight — no equipment needed.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                    } else {
                        crossRefBlock {
                            let items = exercise.equipment.filter { !$0.isDeleted }.sorted { $0.name < $1.name }
                            ForEach(Array(items.enumerated()), id: \.element.persistentModelID) { index, equipment in
                                CrossRefRow(
                                    title: equipment.name,
                                    meta: availableEquipmentNames.contains(equipment.name) ? "" : "not in library"
                                ) {
                                    path = .equipment(equipment)
                                }
                                if index < items.count - 1 {
                                    Divider().overlay(Theme.border)
                                }
                            }
                        }
                    }

                    if let notes = exercise.notes {
                        SheetSectionLabel("NOTES")
                            .padding(.top, 24)
                        NotesBlock(notes)
                    }

                    if let videoURL = exercise.videoURL, let url = URL(string: videoURL) {
                        SheetSectionLabel("VIDEO")
                            .padding(.top, 24)
                        // A quiet key, not a blue link (Quiet Arcade:
                        // Theme.selected is retired as a link color).
                        Link(destination: url) {
                            HStack(spacing: 7) {
                                Image(systemName: "play.rectangle")
                                    .font(.system(.footnote))
                                Text(url.host() ?? videoURL)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 42)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
                        }
                        .buttonStyle(.quietKey)
                    }

                    SheetSectionLabel("ROUTINES (\(usedInRoutines.count))")
                        .padding(.top, 24)
                    if usedInRoutines.isEmpty {
                        Text("Not in any routine yet.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.bottom, 7)
                    } else {
                        crossRefBlock {
                            ForEach(Array(usedInRoutines.enumerated()), id: \.element.persistentModelID) { index, routine in
                                CrossRefRow(title: routine.name, meta: routine.schedule.shortLabel) {
                                    path = .routine(routine)
                                }
                                if index < usedInRoutines.count - 1 {
                                    Divider().overlay(Theme.border)
                                }
                            }
                        }
                        .padding(.bottom, 7)
                    }
                    // Membership as a visible primary action (#265):
                    // buried in the … menu, adding a catalog exercise
                    // read as impossible. Adjacent to — not replacing —
                    // the create row (different intents, and routine
                    // use auto-joins the library anyway); the row
                    // disappearing on tap IS the confirmation. Removal
                    // stays in the … menu: destructive actions live
                    // there (#241).
                    if exercise.isBuiltIn && !exercise.inLibrary {
                        CreateRow(label: "Add to my exercises", identifier: "addToMyExercises") {
                            exercise.inLibrary = true
                        }
                        .padding(.bottom, 7)
                    }
                    CreateRow(label: "New routine with \(exercise.name)", identifier: "newRoutineWithExercise") {
                        newRoutineName = ""
                        showingNewRoutine = true
                    }

                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.background)
        .scrollDismissesKeyboard(.immediately)
        // Custom key chrome (build-42 call). Membership + deletion
        // live behind "…" (#231) — present, not primary, and named for
        // what they touch; edit rides beside it as its own key. A
        // built-in outside the library leaves nothing for the menu, so
        // it hides instead of rendering empty (#265).
        .pushedScreenChrome(title: exercise.name, onBack: { dismiss() }) {
            HeaderIconButton(systemImage: "pencil", identifier: "editExerciseButton") {
                showingEditor = true
            }
            if !exercise.isBuiltIn || exercise.inLibrary {
                HeaderMenuKey(systemImage: "ellipsis", identifier: "exerciseDetailMenu") {
                    if exercise.isBuiltIn {
                        Button("Remove from my exercises", role: .destructive) {
                            exercise.inLibrary = false
                            dismiss()
                        }
                    } else {
                        Button("Delete custom exercise", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                    }
                }
            }
        }
        .navigationDestination(item: $path) { target in
            switch target {
            case .equipment(let equipment): EquipmentDetailScreen(equipment: equipment)
            case .routine(let routine): RoutineDetailView(routine: routine)
            }
        }
        .navigationDestination(item: $createdRoutine) { routine in
            RoutineDetailView(routine: routine)
        }
        .sheet(isPresented: $showingEditor) {
            ExerciseEditorView(editing: exercise)
        }
        .alert("New routine", isPresented: $showingNewRoutine) {
            TextField("Name", text: $newRoutineName)
            Button("Cancel", role: .cancel) { newRoutineName = "" }
            Button("Create") { createRoutine() }
        } message: {
            Text("Starts with \(exercise.name) already in it.")
        }
        .alert("Delete “\(exercise.name)”?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteCustom() }
        } message: {
            if !usedInRoutines.isEmpty {
                Text("It appears in \(usedInRoutines.count) routine\(usedInRoutines.count == 1 ? "" : "s") — it will be removed from them. Logged history keeps its name.")
            } else {
                Text("Logged history keeps its name.")
            }
        }
    }


    private func createRoutine() {
        let name = newRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
        newRoutineName = ""
        guard !name.isEmpty else { return }
        let routine = Routine(name: name, order: 0)
        modelContext.insert(routine)
        for existing in allRoutines where existing !== routine {
            existing.order += 1
        }
        _ = routine.addExerciseInNewGroup(exercise, context: modelContext)
        createdRoutine = routine
    }

    private func deleteCustom() {
        modelContext.delete(exercise)
        dismiss()
    }
}

// MARK: - Equipment detail

struct EquipmentDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var equipment: Equipment

    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt, order: .reverse)])
    private var allRoutines: [Routine]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    @State private var path: PushTarget?
    @State private var showingAddExercise = false
    @State private var showingRename = false
    @State private var confirmingDelete = false
    @State private var renameText = ""

    private enum PushTarget: Hashable {
        case exercise(Exercise)
        case routine(Routine)
    }

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    /// Membership in the ACTIVE library (customs included).
    private var inActiveLibrary: Bool {
        activeLibrary?.contains(equipment) ?? false
    }

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

    /// No opaque "default" (#135): the chips are real numbers, and with
    /// no stored override the unit default's chip reads as selected.
    private static let stepChoices: [Double] = [1, 2.5, 5, 10]

    private var resolvedStep: Double {
        equipment.weightStep ?? weightUnit.step
    }

    private var usedByExercises: [Exercise] {
        allExercises.filter { exercise in
            exercise.equipment.contains { $0 === equipment }
        }
    }

    private var usedInRoutines: [Routine] {
        allRoutines.filter { $0.equipmentNames.contains(equipment.name) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(equipment.isBuiltIn ? "BUILT-IN" : "CUSTOM")
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            .foregroundStyle(equipment.isBuiltIn ? Theme.textSecondary : Theme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(equipment.isBuiltIn ? Theme.borderStrong : Theme.accent.opacity(0.4)))
                    }

                    // Config adapts to the gear (#236): a bench holds
                    // you, a barbell holds plates — only loadables get
                    // a weight step. For customs, the declared exercise
                    // config decides (undeclared customs keep the old
                    // always-loadable default).
                    if SeedData.isLoadable(equipment) {
                        SheetSectionLabel("WEIGHT STEP")
                            .padding(.top, 24)
                        HStack(spacing: 7) {
                            ForEach(Self.stepChoices, id: \.self) { choice in
                                stepChip(choice)
                            }
                        }
                        Text("Per-tap increment for weight exercises using this gear. The wheel picker stays fine-grained.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 6)
                    }

                    // What exercises on this gear track (flexible
                    // metrics): built-in cardio machines carry curated
                    // profiles (shown as facts); custom gear is the
                    // user's to declare — it prefills new exercises and
                    // decides whether the weight step above applies.
                    if equipment.isBuiltIn {
                        if let profile = equipment.suggestedProfile {
                            SheetSectionLabel("EXERCISE CONFIG")
                                .padding(.top, 24)
                            Text(profile.metrics.map(\.label).joined(separator: " · "))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.top, 2)
                            Text("New exercises with this gear start tracking these. Each exercise can change its own set in the editor.")
                                .font(.system(.caption))
                                .foregroundStyle(Theme.textFaint)
                                .padding(.top, 6)
                        }
                    } else {
                        SheetSectionLabel("EXERCISE CONFIG")
                            .padding(.top, 24)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 7)], spacing: 7) {
                            ForEach(WorkoutMetric.allCases.filter { $0 != .rest }) { metric in
                                configMetricChip(metric)
                            }
                        }
                        Text("What exercises on this gear typically track — new exercises with it start from this set. Leave everything off for plain strength gear.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 6)
                    }

                    SheetSectionLabel("EXERCISES (\(usedByExercises.count))")
                        .padding(.top, 24)
                    if usedByExercises.isEmpty {
                        Text("No exercise needs this yet.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.bottom, 7)
                    } else {
                        crossRefBlock {
                            ForEach(Array(usedByExercises.enumerated()), id: \.element.persistentModelID) { index, exercise in
                                CrossRefRow(
                                    title: exercise.name,
                                    meta: exercise.inLibrary || !exercise.isBuiltIn
                                        ? exercise.muscleGroup.displayName.lowercased()
                                        : "not in library"
                                ) {
                                    path = .exercise(exercise)
                                }
                                if index < usedByExercises.count - 1 {
                                    Divider().overlay(Theme.border)
                                }
                            }
                        }
                        .padding(.bottom, 7)
                    }
                    // Same shape as the exercise screen (#265): adding
                    // gear to this library is the primary act on a type
                    // that isn't in it — especially now that the library
                    // gates the catalogs (#260) — so it doesn't hide in
                    // the … menu. Applies to customs too now.
                    if !inActiveLibrary {
                        CreateRow(label: "Add to my equipment", identifier: "addToMyEquipment") {
                            activeLibrary?.setMembership(equipment, true)
                        }
                        .padding(.bottom, 7)
                    }
                    CreateRow(label: "New exercise with \(equipment.name)", identifier: "newExerciseWithEquipment") {
                        showingAddExercise = true
                    }

                    SheetSectionLabel("ROUTINES (\(usedInRoutines.count))")
                        .padding(.top, 24)
                    if usedInRoutines.isEmpty {
                        Text("Not used in any routine yet.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                    } else {
                        crossRefBlock {
                            ForEach(Array(usedInRoutines.enumerated()), id: \.element.persistentModelID) { index, routine in
                                CrossRefRow(title: routine.name, meta: routine.schedule.shortLabel) {
                                    path = .routine(routine)
                                }
                                if index < usedInRoutines.count - 1 {
                                    Divider().overlay(Theme.border)
                                }
                            }
                        }
                    }

                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.background)
        .scrollDismissesKeyboard(.immediately)
        .pushedScreenChrome(title: equipment.name, onBack: { dismiss() }) {
            if !equipment.isBuiltIn {
                HeaderIconButton(systemImage: "pencil", identifier: "renameEquipmentButton") {
                    renameText = equipment.name
                    showingRename = true
                }
            }
            // "Remove" is membership in the active library; "Delete" is
            // the custom's full removal (#265 — destructive in the menu).
            if inActiveLibrary || !equipment.isBuiltIn {
                HeaderMenuKey(systemImage: "ellipsis", identifier: "equipmentDetailMenu") {
                    if inActiveLibrary {
                        Button("Remove from my equipment", role: .destructive) {
                            activeLibrary?.setMembership(equipment, false)
                            dismiss()
                        }
                    }
                    if !equipment.isBuiltIn {
                        Button("Delete custom equipment", role: .destructive) {
                            confirmingDelete = true
                        }
                    }
                }
            }
        }
        // Every other delete in the app confirms; this one was the
        // odd silent one out (reviewer catch), and the dialog carries
        // the reference-stripping consequence the old caption explained.
        .confirmationDialog(
            "Delete \u{201C}\(equipment.name)\u{201D}?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete equipment", role: .destructive) {
                // Belt-and-braces since #196's explicit inverse: strip
                // references first so deletion stays order-independent.
                for exercise in allExercises {
                    exercise.equipment.removeAll { $0 === equipment }
                }
                modelContext.delete(equipment)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be removed from every exercise that references it.")
        }
        .navigationDestination(item: $path) { target in
            switch target {
            case .exercise(let exercise): ExerciseDetailScreen(exercise: exercise)
            case .routine(let routine): RoutineDetailView(routine: routine)
            }
        }
        .sheet(isPresented: $showingAddExercise) {
            ExerciseEditorView(prefillEquipment: equipment)
        }
        .alert("Rename equipment", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename() }
        }
    }

    private func stepChip(_ choice: Double) -> some View {
        let active = resolvedStep == choice
        // Accent-tinted when active: the step is training data (what
        // your plates allow), not chrome.
        return Button {
            equipment.weightStep = choice
        } label: {
            Text(WorkoutMetric.weight.formatted(choice))
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .foregroundStyle(active ? Theme.accent : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .contentShape(Rectangle())
                .background(active ? Theme.accent.opacity(0.16) : Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(active ? Theme.accent.opacity(0.55) : Theme.border))
        }
        .buttonStyle(.plain)
    }

    /// EXERCISE CONFIG chip (custom gear): toggles a metric in the
    /// equipment's suggested profile. Selection blue like every
    /// selected state (#210). An emptied set clears the declaration —
    /// back to "plain strength gear, we can't classify intent".
    private func configMetricChip(_ metric: WorkoutMetric) -> some View {
        let profile = equipment.suggestedProfile
        let selected = profile?.contains(metric) == true
        return Button {
            var metrics = profile?.metrics ?? []
            if let index = metrics.firstIndex(of: metric) {
                metrics.remove(at: index)
            } else {
                metrics.append(metric)
            }
            equipment.suggestedProfile = metrics.isEmpty
                ? nil
                : MetricProfile(metrics, distanceUnit: profile?.distanceUnit ?? .meters)
        } label: {
            Text(metric.label)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(selected ? Theme.onSelected : Theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(selected ? Theme.selected : Theme.background, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("equipmentMetricChip-\(metric.rawValue)")
        .animation(Theme.Anim.selection, value: selected)
    }

    private func rename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !nameClashes(trimmed) else { return }
        equipment.name = trimmed
    }

    /// Case-insensitive clash against every other equipment name.
    private func nameClashes(_ name: String) -> Bool {
        let target = name.lowercased()
        let others = (try? modelContext.fetch(FetchDescriptor<Equipment>())) ?? []
        return others.contains { $0 !== equipment && $0.name.lowercased() == target }
    }
}
