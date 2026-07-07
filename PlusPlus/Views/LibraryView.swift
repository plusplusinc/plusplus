import SwiftUI
import SwiftData
import PlusPlusKit

/// The personal catalog, v3 (#109): LibraryView split into two tabs —
/// Exercises and Equipment — each with its own search and contextual
/// header +. Built-ins removed here leave the library but stay in the
/// catalog; customs are edited or deleted here.
struct ExercisesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @State private var search = ""
    @State private var openSwipeRow: PersistentIdentifier?
    @State private var sheet: LibrarySheet?

    enum LibrarySheet: Identifiable {
        case addExercises
        case editCustom(Exercise)
        case builtInInfo(Exercise)
        case newCustom(prefill: String)

        var id: String {
            switch self {
            case .addExercises: "addExercises"
            case .editCustom(let exercise): "edit-\(exercise.name)"
            case .builtInInfo(let exercise): "info-\(exercise.name)"
            case .newCustom(let prefill): "new-\(prefill)"
            }
        }
    }

    private var libraryExercises: [Exercise] {
        allExercises
            .filter { $0.inLibrary || !$0.isBuiltIn }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            CatalogTabHeader(title: "Exercises", addIdentifier: "addExercisesButton") {
                sheet = .addExercises
            }

            SearchField(prompt: "Search", text: $search)
                .padding(.horizontal, 20)
                .padding(.top, 2)

            List {
                exerciseRows
                Text("swipe left to remove from your library · + browses the full catalog")
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textFaint)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .padding(.top, 4)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Theme.background)
        .sheet(item: $sheet) { destination in
            switch destination {
            case .addExercises:
                AddFromCatalogSheet(kind: .exercises) { prefill in
                    sheet = .newCustom(prefill: prefill)
                }
            case .editCustom(let exercise):
                ExerciseEditorView(editing: exercise)
            case .builtInInfo(let exercise):
                BuiltInInfoSheet(exercise: exercise)
                    .presentationDetents([.medium])
            case .newCustom(let prefill):
                ExerciseEditorView(prefillName: prefill)
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var exerciseRows: some View {
        ForEach(libraryExercises) { exercise in
            SwipeRevealRow(id: exercise.persistentModelID, openRow: $openSwipeRow, actionsWidth: 58) {
            Button {
                if openSwipeRow != nil {
                    openSwipeRow = nil
                } else {
                    sheet = exercise.isBuiltIn ? .builtInInfo(exercise) : .editCustom(exercise)
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(exercise.name)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(subtitle(for: exercise))
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if !exercise.isBuiltIn {
                        Text("CUSTOM")
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4)))
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            } actions: {
                SwipeActionButton(label: "REMOVE", color: Theme.destructive) {
                    openSwipeRow = nil
                    remove(exercise)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Theme.border)
        }
    }

    private func subtitle(for exercise: Exercise) -> String {
        let equipment = exercise.equipment.map(\.name).sorted().joined(separator: ", ")
        var subtitle = "\(exercise.muscleGroup.displayName) · \(equipment.isEmpty ? "Bodyweight" : equipment)"
        // Curated items are never hidden by ownership (#113) — your
        // library is yours — but the gap is flagged.
        let missing = ExerciseFilterState.missingEquipment(for: exercise)
        if !missing.isEmpty {
            subtitle += " · needs \(missing.joined(separator: ", "))"
        }
        return subtitle
    }

    private func remove(_ exercise: Exercise) {
        if exercise.isBuiltIn {
            exercise.inLibrary = false
        } else {
            modelContext.delete(exercise)
        }
    }
}

/// The Equipment tab (#109): what you own. Feeds exercise filtering;
/// the v3 onboarding preset picker (#113) writes this same list.
struct EquipmentTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]

    @State private var search = ""
    @State private var openSwipeRow: PersistentIdentifier?
    @State private var showingAdd = false
    @State private var selectedEquipment: Equipment?

    private var libraryEquipment: [Equipment] {
        allEquipment
            .filter { $0.inLibrary || !$0.isBuiltIn }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            CatalogTabHeader(title: "Equipment", addIdentifier: "addEquipmentButton") {
                showingAdd = true
            }

            SearchField(prompt: "Search", text: $search)
                .padding(.horizontal, 20)
                .padding(.top, 2)

            List {
                equipmentRows
                Text("swipe left to remove from your library · + browses the catalog or creates custom gear")
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textFaint)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .padding(.top, 4)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Theme.background)
        .sheet(isPresented: $showingAdd) {
            AddFromCatalogSheet(kind: .equipment) { _ in }
        }
        .sheet(item: $selectedEquipment) { equipment in
            EquipmentDetailSheet(equipment: equipment) {
                selectedEquipment = nil
                remove(equipment)
            }
        }
    }

    @ViewBuilder
    private var equipmentRows: some View {
        ForEach(libraryEquipment) { equipment in
            SwipeRevealRow(id: equipment.persistentModelID, openRow: $openSwipeRow, actionsWidth: 58) {
            Button {
                if openSwipeRow != nil {
                    openSwipeRow = nil
                } else {
                    selectedEquipment = equipment
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(equipment.name)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(equipmentSubtitle(for: equipment))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            } actions: {
                SwipeActionButton(label: "REMOVE", color: Theme.destructive) {
                    openSwipeRow = nil
                    remove(equipment)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Theme.border)
        }
    }

    private func equipmentSubtitle(for equipment: Equipment) -> String {
        let used = allExercises.filter { $0.equipment.contains(where: { $0 === equipment }) }.count
        var text = used == 0 ? "unused" : (used == 1 ? "1 exercise" : "\(used) exercises")
        if !equipment.isBuiltIn { text += " · custom" }
        return text
    }

    private func remove(_ equipment: Equipment) {
        if equipment.isBuiltIn {
            equipment.inLibrary = false
        } else {
            // Exercise→Equipment has no inverse, so SwiftData can't
            // nullify referencing exercises on deletion — strip the
            // references first or they dangle (bug hunt B1).
            for exercise in allExercises {
                exercise.equipment.removeAll { $0 === equipment }
            }
            modelContext.delete(equipment)
        }
    }
}

/// Shared header for the two catalog tabs: ++ glyph, title, and the
/// contextual + button.
struct CatalogTabHeader: View {
    let title: String
    var addIdentifier: String?
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HeaderGlyph()
                Spacer()
                HeaderIconButton(systemImage: "plus", identifier: addIdentifier) {
                    onAdd()
                }
            }
            Text(title)
                .font(.system(.title, weight: .bold))
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

// MARK: - Add from catalog

/// Bottom sheet browsing the not-yet-in-library catalog (#63); `+ Add`
/// flips membership, the dashed row creates a custom entry.
struct AddFromCatalogSheet: View {
    enum Kind: String, Identifiable {
        case exercises
        case equipment

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]

    let kind: Kind
    /// Called with the current query when "Create custom…" is tapped
    /// (exercises only — the parent presents the editor).
    let onCreateCustom: (String) -> Void

    @State private var query = ""
    @State private var showUnowned = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text(kind == .exercises ? "Add exercises" : "Add equipment")
                    .font(.system(.subheadline, weight: .bold))
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button("Done") { dismiss() }
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            SearchField(prompt: "Search the catalog", text: $query, fill: Theme.background)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Button {
                createCustom()
            } label: {
                HStack(spacing: 8) {
                    Text("+").font(.system(.subheadline, design: .monospaced))
                    Text(createLabel).font(.system(.footnote, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            List {
                if kind == .exercises {
                    ForEach(candidateExercises) { exercise in
                        catalogRow(
                            name: exercise.name,
                            sub: exerciseSubtitle(exercise)
                        ) {
                            exercise.inLibrary = true
                        }
                    }
                    // #113: hidden-by-ownership escape hatch.
                    Button {
                        showUnowned.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: showUnowned ? "checkmark.square" : "square")
                                .font(.system(.caption))
                            Text("show exercises needing equipment I don't have")
                                .font(.system(.caption))
                        }
                        .foregroundStyle(showUnowned ? Theme.textPrimary : Theme.textSecondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(candidateEquipment) { equipment in
                        catalogRow(name: equipment.name, sub: "catalog") {
                            equipment.inLibrary = true
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.top, 2)
        }
        .presentationBackground(Theme.surface)
        .presentationDetents([.fraction(0.8)])
    }

    private var createLabel: String {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return "Create “\(trimmed)”" }
        return kind == .exercises ? "Create custom exercise…" : "Create custom equipment…"
    }

    private var candidateExercises: [Exercise] {
        allExercises
            .filter { $0.isBuiltIn && !$0.inLibrary }
            .filter { showUnowned || ExerciseFilterState.missingEquipment(for: $0).isEmpty }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var candidateEquipment: [Equipment] {
        allEquipment
            .filter { $0.isBuiltIn && !$0.inLibrary }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func exerciseSubtitle(_ exercise: Exercise) -> String {
        let equipment = exercise.equipment.map(\.name).sorted().joined(separator: ", ")
        var subtitle = "\(exercise.muscleGroup.displayName) · \(equipment.isEmpty ? "Bodyweight" : equipment)"
        let missing = ExerciseFilterState.missingEquipment(for: exercise)
        if !missing.isEmpty {
            subtitle += " · needs \(missing.joined(separator: ", "))"
        }
        return subtitle
    }

    private func catalogRow(name: String, sub: String, onAdd: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(.subheadline, weight: .semibold)).lineLimit(1)
                Text(sub).font(.system(.caption)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            Button(action: onAdd) {
                Text("+ Add")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.opacity(0.4)))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Theme.border)
    }

    private func createCustom() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if kind == .equipment {
            guard !trimmed.isEmpty else { return }
            let existing = allEquipment.first { $0.name.lowercased() == trimmed.lowercased() }
            if let existing {
                existing.inLibrary = true
            } else {
                modelContext.insert(Equipment(name: trimmed, isBuiltIn: false))
            }
            dismiss()
        } else {
            dismiss()
            onCreateCustom(trimmed)
        }
    }
}

// MARK: - Equipment detail

/// Tapping a piece of gear opens this (Dave, build 12): the weight
/// step it implies, the exercises that need it, and the workouts it
/// appears in. Removal lives here too, mirroring the swipe action.
struct EquipmentDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: [SortDescriptor(\Workout.order), SortDescriptor(\Workout.createdAt, order: .reverse)])
    private var allWorkouts: [Workout]

    @Bindable var equipment: Equipment
    /// Parent-owned removal (built-in → leaves library; custom →
    /// strips references and deletes). The sheet is dismissed first.
    let onRemove: () -> Void

    /// nil = the unit default (5 lb / 2.5 kg).
    private static let stepChoices: [Double?] = [nil, 1, 2.5, 5, 10]

    private var usedByExercises: [Exercise] {
        allExercises.filter { exercise in
            exercise.equipment.contains { $0 === equipment }
        }
    }

    private var usedInWorkouts: [Workout] {
        allWorkouts.filter { $0.equipmentNames.contains(equipment.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(equipment.name)
                    .font(.system(.title3, weight: .bold))
                Spacer()
                Text(equipment.isBuiltIn ? "BUILT-IN" : "CUSTOM")
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .foregroundStyle(equipment.isBuiltIn ? Theme.textSecondary : Theme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(equipment.isBuiltIn ? Theme.borderStrong : Theme.accent.opacity(0.4)))
            }
            .padding(.top, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SheetSectionLabel("WEIGHT STEP")
                        .padding(.top, 18)
                    HStack(spacing: 7) {
                        ForEach(Self.stepChoices, id: \.self) { choice in
                            stepChip(choice)
                        }
                    }
                    Text("per-tap increment for weight exercises using this gear · the wheel stays fine-grained")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 6)

                    SheetSectionLabel("EXERCISES (\(usedByExercises.count))")
                        .padding(.top, 18)
                    if usedByExercises.isEmpty {
                        Text("nothing in the catalog needs this")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                    } else {
                        listBlock(usedByExercises.map { exercise in
                            (exercise.name, exercise.inLibrary || !exercise.isBuiltIn
                                ? exercise.muscleGroup.displayName
                                : "\(exercise.muscleGroup.displayName) · not in library")
                        })
                    }

                    SheetSectionLabel("WORKOUTS (\(usedInWorkouts.count))")
                        .padding(.top, 18)
                    if usedInWorkouts.isEmpty {
                        Text("not used in any workout yet")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                    } else {
                        listBlock(usedInWorkouts.map { workout in
                            (workout.name, workout.schedule.shortLabel)
                        })
                    }

                    SheetActionButton(
                        equipment.isBuiltIn ? "Remove from my library" : "Delete custom equipment",
                        destructive: true
                    ) {
                        dismiss()
                        onRemove()
                    }
                    .padding(.top, 22)

                    if !equipment.isBuiltIn {
                        Text("removes it from every exercise that references it")
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
        .presentationDetents([.medium, .large])
    }

    private func stepChip(_ choice: Double?) -> some View {
        let active = equipment.weightStep == choice
        // Accent-tinted when active: the step is training data (what
        // your plates allow), not chrome.
        return Button {
            equipment.weightStep = choice
        } label: {
            Text(choice.map { WorkoutMetric.weight.formatted($0) } ?? "default")
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .foregroundStyle(active ? Theme.accent : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(active ? Theme.accent.opacity(0.16) : Theme.background, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(active ? Theme.accent.opacity(0.55) : Theme.border))
        }
        .buttonStyle(.plain)
    }

    private func listBlock(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 8) {
                    Text(row.0)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(row.1)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                if index < rows.count - 1 {
                    Divider().overlay(Theme.border)
                }
            }
        }
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
    }
}

// MARK: - Built-in info

/// Read-only sheet for catalog exercises (#63): they can't be edited,
/// only removed from the personal library.
struct BuiltInInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Theme.borderStrong).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            HStack(spacing: 8) {
                Text(exercise.name)
                    .font(.system(.title3, weight: .bold))
                Spacer()
                Text("BUILT-IN")
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(Theme.borderStrong))
            }
            .padding(.top, 10)

            HStack(spacing: 6) {
                ChipLabel(exercise.muscleGroup.displayName)
                ChipLabel(exercise.equipment.isEmpty
                          ? "Bodyweight"
                          : exercise.equipment.map(\.name).sorted().joined(separator: ", "))
            }
            .padding(.top, 8)

            if let notes = exercise.notes {
                NotesBlock(notes)
                    .padding(.top, 13)
            }

            Text("Catalog exercises can't be edited — create a custom one to tweak.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 14)

            SheetActionButton("Remove from my library", destructive: true) {
                exercise.inLibrary = false
                dismiss()
            }
            .padding(.top, 14)

            SheetActionButton("Close") { dismiss() }
                .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 18)
        .presentationBackground(Theme.surface)
    }
}
