import SwiftUI
import SwiftData
import PlusPlusKit

/// Pushed detail screens for the two catalog tabs (#137): the catalog
/// is a navigable graph, not three isolated lists. Equipment links to
/// the exercises that need it, exercises link to the workouts that
/// contain them, and every dead end offers creation — chains push in
/// place with standard back navigation. Sheets survive only for
/// create/edit forms.

/// Back-button + title header shared by the pushed catalog screens,
/// mirroring WorkoutDetailView's pattern (custom quiet-terminal header,
/// system navigation bar hidden).
struct CatalogDetailHeader<Trailing: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(.footnote, weight: .bold))
                    Text("Back")
                        .font(.system(.footnote, weight: .semibold))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 6)
            }
            .accessibilityIdentifier("backButton")

            HStack(alignment: .center) {
                Text(title)
                    .font(.system(.title, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                trailing()
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

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
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
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

    @Query(sort: [SortDescriptor(\Workout.order), SortDescriptor(\Workout.createdAt, order: .reverse)])
    private var allWorkouts: [Workout]

    @State private var path: PushTarget?
    @State private var showingEditor = false
    @State private var showingNewWorkout = false
    @State private var newWorkoutName = ""
    @State private var showingDeleteConfirm = false
    /// A workout created from here pushes immediately — the fluid-nav
    /// promise: create it with this exercise already inside, land in it.
    @State private var createdWorkout: Workout?

    private enum PushTarget: Hashable {
        case equipment(Equipment)
        case workout(Workout)
    }

    private var usedInWorkouts: [Workout] {
        allWorkouts.filter { workout in
            workout.sortedGroups.flatMap(\.sortedExercises).contains { $0.exercise === exercise }
        }
    }

    private var typeLabel: String {
        exercise.exerciseType == .duration ? "Duration" : "Weight & reps"
    }

    var body: some View {
        VStack(spacing: 0) {
            CatalogDetailHeader(title: exercise.name) {
                HeaderIconButton(systemImage: "pencil", identifier: "editExerciseButton") {
                    showingEditor = true
                }
            }

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
                        .padding(.top, 18)
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
                                    meta: equipment.inLibrary || !equipment.isBuiltIn ? "" : "not in library"
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
                            .padding(.top, 18)
                        NotesBlock(notes)
                    }

                    if let videoURL = exercise.videoURL, let url = URL(string: videoURL) {
                        SheetSectionLabel("VIDEO")
                            .padding(.top, 18)
                        Link(destination: url) {
                            HStack(spacing: 7) {
                                Image(systemName: "play.rectangle")
                                    .font(.system(.footnote))
                                Text(url.host() ?? videoURL)
                                    .font(.system(.footnote, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Theme.info)
                        }
                    }

                    SheetSectionLabel("WORKOUTS (\(usedInWorkouts.count))")
                        .padding(.top, 18)
                    if usedInWorkouts.isEmpty {
                        Text("Not in any workout yet.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.bottom, 7)
                    } else {
                        crossRefBlock {
                            ForEach(Array(usedInWorkouts.enumerated()), id: \.element.persistentModelID) { index, workout in
                                CrossRefRow(title: workout.name, meta: workout.schedule.shortLabel) {
                                    path = .workout(workout)
                                }
                                if index < usedInWorkouts.count - 1 {
                                    Divider().overlay(Theme.border)
                                }
                            }
                        }
                        .padding(.bottom, 7)
                    }
                    CreateRow(label: "New workout with \(exercise.name)", identifier: "newWorkoutWithExercise") {
                        newWorkoutName = ""
                        showingNewWorkout = true
                    }

                    libraryActions
                        .padding(.top, 22)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $path) { target in
            switch target {
            case .equipment(let equipment): EquipmentDetailScreen(equipment: equipment)
            case .workout(let workout): WorkoutDetailView(workout: workout)
            }
        }
        .navigationDestination(item: $createdWorkout) { workout in
            WorkoutDetailView(workout: workout)
        }
        .sheet(isPresented: $showingEditor) {
            ExerciseEditorView(editing: exercise)
        }
        .alert("New workout", isPresented: $showingNewWorkout) {
            TextField("Name", text: $newWorkoutName)
            Button("Cancel", role: .cancel) { newWorkoutName = "" }
            Button("Create") { createWorkout() }
        } message: {
            Text("Starts with \(exercise.name) already in it.")
        }
        .alert("Delete “\(exercise.name)”?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteCustom() }
        } message: {
            if !usedInWorkouts.isEmpty {
                Text("It appears in \(usedInWorkouts.count) workout\(usedInWorkouts.count == 1 ? "" : "s") — it will be removed from them. Logged history keeps its name.")
            } else {
                Text("Logged history keeps its name.")
            }
        }
    }

    @ViewBuilder
    private var libraryActions: some View {
        if exercise.isBuiltIn {
            if exercise.inLibrary {
                SheetActionButton("Remove from my library", destructive: true) {
                    exercise.inLibrary = false
                    dismiss()
                }
            } else {
                SheetActionButton("Add to my library") {
                    exercise.inLibrary = true
                }
            }
        } else {
            SheetActionButton("Delete custom exercise", destructive: true) {
                showingDeleteConfirm = true
            }
        }
    }

    private func createWorkout() {
        let name = newWorkoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        newWorkoutName = ""
        guard !name.isEmpty else { return }
        let workout = Workout(name: name, order: 0)
        modelContext.insert(workout)
        for existing in allWorkouts where existing !== workout {
            existing.order += 1
        }
        _ = workout.addExerciseInNewGroup(exercise, context: modelContext)
        createdWorkout = workout
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
    @Query(sort: [SortDescriptor(\Workout.order), SortDescriptor(\Workout.createdAt, order: .reverse)])
    private var allWorkouts: [Workout]

    @State private var path: PushTarget?
    @State private var showingAddExercise = false
    @State private var showingRename = false
    @State private var renameText = ""

    private enum PushTarget: Hashable {
        case exercise(Exercise)
        case workout(Workout)
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

    private var usedInWorkouts: [Workout] {
        allWorkouts.filter { $0.equipmentNames.contains(equipment.name) }
    }

    var body: some View {
        VStack(spacing: 0) {
            CatalogDetailHeader(title: equipment.name) {
                if !equipment.isBuiltIn {
                    HeaderIconButton(systemImage: "pencil", identifier: "renameEquipmentButton") {
                        renameText = equipment.name
                        showingRename = true
                    }
                }
            }

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

                    SheetSectionLabel("WEIGHT STEP")
                        .padding(.top, 18)
                    HStack(spacing: 7) {
                        ForEach(Self.stepChoices, id: \.self) { choice in
                            stepChip(choice)
                        }
                    }
                    Text("Per-tap increment for weight exercises using this gear. The wheel picker stays fine-grained.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 6)

                    SheetSectionLabel("EXERCISES (\(usedByExercises.count))")
                        .padding(.top, 18)
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
                    CreateRow(label: "New exercise with \(equipment.name)", identifier: "newExerciseWithEquipment") {
                        showingAddExercise = true
                    }

                    SheetSectionLabel("WORKOUTS (\(usedInWorkouts.count))")
                        .padding(.top, 18)
                    if usedInWorkouts.isEmpty {
                        Text("Not used in any workout yet.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                    } else {
                        crossRefBlock {
                            ForEach(Array(usedInWorkouts.enumerated()), id: \.element.persistentModelID) { index, workout in
                                CrossRefRow(title: workout.name, meta: workout.schedule.shortLabel) {
                                    path = .workout(workout)
                                }
                                if index < usedInWorkouts.count - 1 {
                                    Divider().overlay(Theme.border)
                                }
                            }
                        }
                    }

                    libraryActions
                        .padding(.top, 22)
                    if !equipment.isBuiltIn {
                        Text("Deleting removes it from every exercise that references it.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $path) { target in
            switch target {
            case .exercise(let exercise): ExerciseDetailScreen(exercise: exercise)
            case .workout(let workout): WorkoutDetailView(workout: workout)
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

    @ViewBuilder
    private var libraryActions: some View {
        if equipment.isBuiltIn {
            if equipment.inLibrary {
                SheetActionButton("Remove from my library", destructive: true) {
                    equipment.inLibrary = false
                    dismiss()
                }
            } else {
                SheetActionButton("Add to my library") {
                    equipment.inLibrary = true
                }
            }
        } else {
            SheetActionButton("Delete custom equipment", destructive: true) {
                // Exercise→Equipment has no inverse, so SwiftData can't
                // nullify referencing exercises on deletion — strip the
                // references first or they dangle (bug hunt B1).
                for exercise in allExercises {
                    exercise.equipment.removeAll { $0 === equipment }
                }
                modelContext.delete(equipment)
                dismiss()
            }
        }
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
