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
    @State private var createdRoutine: IdentifiedUUID?

    private enum PushTarget: Hashable {
        case equipment(Equipment)
        case routine(UUID)
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
                    // The name is a large, left-aligned body header that wraps
                    // to two lines (2026-07-18) — the centered chrome title
                    // truncated long names; every detail screen now leads with
                    // the name in the body, matching RoutineDetailView.
                    Text(exercise.name)
                        .font(.system(.title, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 4)
                        .padding(.bottom, 14)
                    // The shared card capsule vocabulary (2026-07-19): soft
                    // tags in natural case (no stroked ALL-CAPS), the same as
                    // the rows and the routine header. Muscle ↔ the Muscle
                    // filter; type = what it tracks; a Custom tag for customs.
                    DetailHeaderCapsules(capsules: {
                        var caps = [
                            CardCapsule(text: exercise.muscleGroup.displayName),
                            CardCapsule(text: typeLabel),
                        ]
                        if !exercise.isBuiltIn {
                            caps.append(CardCapsule(text: "Custom", tint: Theme.accent))
                        }
                        return caps
                    }())

                    SheetSectionLabel("EQUIPMENT")
                        .padding(.top, 24)
                    if exercise.equipment.isEmpty {
                        Text("Bodyweight. No equipment needed.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                    } else {
                        crossRefBlock {
                            let items = exercise.equipment.filter { !$0.isDeleted }.sorted { $0.name < $1.name }
                            ForEach(Array(items.enumerated()), id: \.element.persistentModelID) { index, equipment in
                                CrossRefRow(
                                    title: equipment.name,
                                    meta: availableEquipmentNames.contains(equipment.name) ? "" : "not in kit"
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

                    // The app's own demo leads; the external video link
                    // below stays as the fallback.
                    if let animation = MascotMoves.animation(forExerciseNamed: exercise.name) {
                        SheetSectionLabel("FORM")
                            .padding(.top, 24)
                        MascotFormCard(exerciseName: exercise.name, animation: animation)
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
                                    routine.uuid.map { path = .routine($0) }
                                }
                                if index < usedInRoutines.count - 1 {
                                    Divider().overlay(Theme.border)
                                }
                            }
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
        .pushedScreenChrome(title: "", onBack: { dismiss() }) {
            // Favorite is the curation now (whole catalog, 2026-07-17):
            // a star for everything, accent when lit. Removal/deletion of
            // the old library membership is gone; only a custom keeps a
            // destructive action.
            HeaderIconButton(
                systemImage: exercise.isFavorite ? "star.fill" : "star",
                accessibilityLabel: exercise.isFavorite ? "Unfavorite exercise" : "Favorite exercise",
                identifier: "favoriteExerciseButton",
                tint: exercise.isFavorite ? Theme.accent : Theme.textSecondary
            ) {
                exercise.isFavorite.toggle()
            }
            HeaderIconButton(systemImage: "pencil", accessibilityLabel: "Edit exercise", identifier: "editExerciseButton") {
                showingEditor = true
            }
            if !exercise.isBuiltIn {
                HeaderMenuKey(systemImage: "ellipsis", accessibilityLabel: "Exercise options", identifier: "exerciseDetailMenu") {
                    Button("Delete custom exercise", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                }
            }
        }
        .navigationDestination(item: $path) { target in
            switch target {
            case .equipment(let equipment): EquipmentDetailScreen(equipment: equipment)
            case .routine(let uuid):
                if let routine = modelContext.routine(uuid: uuid) {
                    RoutineDetailView(routine: routine)
                }
            }
        }
        .navigationDestination(item: $createdRoutine) { ref in
            if let routine = modelContext.routine(uuid: ref.id) {
                RoutineDetailView(routine: routine)
            }
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
                Text("It appears in \(usedInRoutines.count) routine\(usedInRoutines.count == 1 ? "" : "s") and will be removed from them. Logged history keeps its name.")
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
        // Permanent id before we navigate: .navigationDestination(item:)
        // keys on persistentModelID, which SwiftData swaps temporary→
        // permanent at the first save — a later autosave firing while the
        // pushed RoutineDetailView is up would re-key the destination and
        // tear it down/re-push (the tray-flicker class; swiftdata.md).
        try? modelContext.save()
        createdRoutine = routine.uuid.map(IdentifiedUUID.init)
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
    /// Setup context (onboarding + the Settings re-run) strips the screen
    /// to the add-and-configure task: the exercises/routines cross-links
    /// distract from it (Dave, 2026-07-17). Off in the Equipment tab.
    var isOnboarding = false

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
    @State private var showingStepSheet = false

    private enum PushTarget: Hashable {
        case exercise(Exercise)
        case routine(UUID)
    }

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    /// Membership in the ACTIVE library (customs included).
    private var inActiveLibrary: Bool {
        activeLibrary?.contains(equipment) ?? false
    }

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

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
                    // Name as a large, left-aligned wrapping body header
                    // (2026-07-18) — consistent with every other detail screen.
                    Text(equipment.name)
                        .font(.system(.title, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 4)
                        .padding(.bottom, 14)
                    // The shared card capsule vocabulary (2026-07-19): soft
                    // tags in natural case, matching the equipment row (category
                    // ↔ the Type filter; a Custom tag for customs).
                    DetailHeaderCapsules(capsules: {
                        var caps: [CardCapsule] = []
                        if let category = SeedData.equipmentCategory(named: equipment.name) {
                            caps.append(CardCapsule(text: category.rawValue))
                        }
                        if !equipment.isBuiltIn {
                            caps.append(CardCapsule(text: "Custom", tint: Theme.accent))
                        }
                        return caps
                    }())

                    // The whole point of the screen: do you have this gear?
                    // A prominent toggle card (Dave, 2026-07-17) so the
                    // action is unmistakable — flip it on to add, off to
                    // remove. Removal no longer hides in the … menu.
                    kitToggleCard
                        .padding(.top, 14)

                    // Weight step is the only per-gear configurable now
                    // (Tracks removed, 2026-07-17: metrics belong to the
                    // exercise, not the gear). Only loadable gear carries
                    // it (#236: a bench holds you, a barbell holds plates),
                    // so non-loadables show no CONFIGURE section at all.
                    if SeedData.isLoadable(equipment) {
                        SheetSectionLabel("CONFIGURE")
                            .padding(.top, 24)
                        configRow(
                            label: "Weight step",
                            value: WorkoutMetric.weight.displayText(resolvedStep, weightUnit: weightUnit),
                            identifier: "configWeightStepRow"
                        ) { showingStepSheet = true }
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
                        .padding(.top, 7)
                    }

                    // The exercise/routine graph (#137) is exploration, not
                    // the setup task — hidden during onboarding, present in
                    // the Equipment tab (Dave, 2026-07-17).
                    if !isOnboarding {
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
                                        meta: exercise.muscleGroup.displayName.lowercased()
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
                                        routine.uuid.map { path = .routine($0) }
                                    }
                                    if index < usedInRoutines.count - 1 {
                                        Divider().overlay(Theme.border)
                                    }
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
        .pushedScreenChrome(title: "", onBack: { dismiss() }) {
            if !equipment.isBuiltIn {
                HeaderIconButton(systemImage: "pencil", accessibilityLabel: "Rename equipment", identifier: "renameEquipmentButton") {
                    renameText = equipment.name
                    showingRename = true
                }
            }
            // Membership is the toggle card now; the menu is only the
            // custom's destructive delete (built-ins have nothing here).
            if !equipment.isBuiltIn {
                HeaderMenuKey(systemImage: "ellipsis", accessibilityLabel: "Equipment options", identifier: "equipmentDetailMenu") {
                    Button("Delete custom equipment", role: .destructive) {
                        confirmingDelete = true
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
            case .routine(let uuid):
                if let routine = modelContext.routine(uuid: uuid) {
                    RoutineDetailView(routine: routine)
                }
            }
        }
        .sheet(isPresented: $showingAddExercise) {
            ExerciseEditorView(prefillEquipment: [equipment])
        }
        .sheet(isPresented: $showingStepSheet) {
            IncrementSheet(
                metric: .weight,
                weightUnit: weightUnit,
                distanceUnit: equipment.suggestedProfile?.distanceUnit ?? .meters,
                current: resolvedStep,
                onPick: { equipment.weightStep = $0 }
            )
        }
        .alert("Rename equipment", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename() }
        }
    }

    /// Membership as a Binding so the toggle drives it directly.
    private var membershipBinding: Binding<Bool> {
        Binding(
            get: { inActiveLibrary },
            set: { activeLibrary?.setMembership(equipment, $0) }
        )
    }

    /// The prominent "do you have this?" card (Dave, 2026-07-17): an obvious
    /// card so it's unmistakable that adding gear takes an action, and
    /// removal lives in the same spot. The WHOLE card is the tap target
    /// (Dave, 2026-07-18): the `Toggle` stays the interactive control (so
    /// the switch is directly usable and VoiceOver-idiomatic), and an
    /// `.onTapGesture` on the card flips the SAME binding from anywhere
    /// else on it — both paths drive `membershipBinding`, so a tap resolves
    /// to exactly one flip whichever gesture wins. Accent green = you have
    /// it (matches the catalog's in-kit glyph + the quick-add).
    /// The active kit's name for prose, but only once more than one kit
    /// exists — a lone default kit reads better as "your kit" than the bare
    /// lowercase "main" (copy + swift review, 2026-07-20). Matches the
    /// app's "name the active kit once more than one exists" grammar.
    private var kitPhrase: String {
        libraries.count > 1 ? (activeLibrary?.name ?? EquipmentLibrary.defaultName) : "your kit"
    }

    private var kitToggleCard: some View {
        let inKit = inActiveLibrary
        // Name the target kit right in the card (Dave, 2026-07-20) so the
        // add is never a guess about which kit is active.
        let kitName = kitPhrase
        return HStack(spacing: 14) {
            Image(systemName: inKit ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(.title2))
                .foregroundStyle(inKit ? Theme.accent : Theme.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(inKit ? "In \(kitName)" : "Add to \(kitName)")
                    .font(.system(.headline))
                    .foregroundStyle(Theme.textPrimary)
                Text(inKit ? "You have this equipment." : "Add it if you train with it.")
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: membershipBinding)
                .labelsHidden()
                .tint(Theme.accent)
                .accessibilityIdentifier("addToMyEquipment")
                .accessibilityLabel(inKit ? "Remove from \(kitName)" : "Add to \(kitName)")
        }
        .padding(16)
        .background(
            inKit ? Theme.accent.opacity(0.08) : Theme.surface,
            in: RoundedRectangle(cornerRadius: Theme.controlRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius)
                .strokeBorder(inKit ? Theme.accent.opacity(0.4) : Theme.borderStrong)
        )
        .contentShape(Rectangle())
        .onTapGesture { membershipBinding.wrappedValue.toggle() }
        .animation(Theme.Anim.selection, value: inKit)
    }

    /// One configurable fact per row: label, the resolved value, and the
    /// app's one configuration glyph (ConfigIconButton) opening its
    /// sheet. The whole row is tappable — the glyph is the signpost.
    private func configRow(label: String, value: String, identifier: String, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
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
