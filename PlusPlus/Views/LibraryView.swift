import SwiftUI
import SwiftData
import PlusPlusKit

/// The personal library, v2 (#63): the curated set of exercises and
/// equipment the picker draws from. Built-ins removed here leave the
/// library but stay in the catalog; customs are edited or deleted here.
struct LibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]

    private enum Tab: String, CaseIterable {
        case exercises = "Exercises"
        case equipment = "Equipment"
    }

    @State private var tab: Tab = .exercises
    @State private var search = ""
    @State private var sheet: LibrarySheet?

    enum LibrarySheet: Identifiable {
        case addExercises
        case addEquipment
        case editCustom(Exercise)
        case builtInInfo(Exercise)
        case newCustom(prefill: String)

        var id: String {
            switch self {
            case .addExercises: "addExercises"
            case .addEquipment: "addEquipment"
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

    private var libraryEquipment: [Equipment] {
        allEquipment
            .filter { $0.inLibrary || !$0.isBuiltIn }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            searchRow
                .padding(.horizontal, 20)
                .padding(.top, 12)

            List {
                if tab == .exercises {
                    exerciseRows
                } else {
                    equipmentRows
                }
                Text(tab == .exercises
                     ? "swipe ← to remove from your library · + Add browses the full catalog"
                     : "swipe ← to remove from your library · + Add browses the catalog or creates custom gear")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textFaint)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .padding(.top, 4)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { destination in
            switch destination {
            case .addExercises:
                AddFromCatalogSheet(kind: .exercises) { prefill in
                    sheet = .newCustom(prefill: prefill)
                }
            case .addEquipment:
                AddFromCatalogSheet(kind: .equipment) { _ in }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                    Text("Workouts").font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 6)
            }
            .accessibilityIdentifier("backButton")

            Text("Library")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 2)

            SegmentedTabs(
                options: Tab.allCases.map(\.rawValue),
                selectedIndex: Binding(
                    get: { tab == .exercises ? 0 : 1 },
                    set: { tab = $0 == 0 ? .exercises : .equipment; search = "" }
                )
            )
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textFaint)
                TextField("Search", text: $search)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))

            Button {
                sheet = tab == .exercises ? .addExercises : .addEquipment
            } label: {
                HStack(spacing: 5) {
                    Text("+").font(.system(size: 14, design: .monospaced))
                    Text("Add").font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 13)
                .frame(height: 38)
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong))
            }
            .accessibilityIdentifier("libraryAddButton")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var exerciseRows: some View {
        ForEach(libraryExercises) { exercise in
            Button {
                sheet = exercise.isBuiltIn ? .builtInInfo(exercise) : .editCustom(exercise)
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(exercise.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(subtitle(for: exercise))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if !exercise.isBuiltIn {
                        Text("CUSTOM")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4)))
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Theme.border)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: exercise.isBuiltIn ? nil : .destructive) {
                    remove(exercise)
                } label: {
                    Label("Remove", systemImage: "xmark")
                }
                .tint(Theme.destructiveFill)
            }
        }
    }

    @ViewBuilder
    private var equipmentRows: some View {
        ForEach(libraryEquipment) { equipment in
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(equipment.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text(equipmentSubtitle(for: equipment))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Theme.border)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    remove(equipment)
                } label: {
                    Label("Remove", systemImage: "xmark")
                }
                .tint(Theme.destructiveFill)
            }
        }
    }

    private func subtitle(for exercise: Exercise) -> String {
        let equipment = exercise.equipment.map(\.name).sorted().joined(separator: ", ")
        return "\(exercise.muscleGroup.displayName) · \(equipment.isEmpty ? "Bodyweight" : equipment)"
    }

    private func equipmentSubtitle(for equipment: Equipment) -> String {
        let used = allExercises.filter { $0.equipment.contains(where: { $0 === equipment }) }.count
        var text = used == 0 ? "unused" : (used == 1 ? "1 exercise" : "\(used) exercises")
        if !equipment.isBuiltIn { text += " · custom" }
        return text
    }

    private func remove(_ exercise: Exercise) {
        if exercise.isBuiltIn {
            exercise.inLibrary = false
        } else {
            modelContext.delete(exercise)
        }
    }

    private func remove(_ equipment: Equipment) {
        if equipment.isBuiltIn {
            equipment.inLibrary = false
        } else {
            modelContext.delete(equipment)
        }
    }
}

/// v2 segmented control (green fill on the active tab).
struct SegmentedTabs: View {
    let options: [String]
    @Binding var selectedIndex: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    selectedIndex = index
                } label: {
                    Text(option)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(selectedIndex == index ? .white : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            selectedIndex == index ? Theme.accentButton : .clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
            }
        }
        .padding(3)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text(kind == .exercises ? "Add exercises" : "Add equipment")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button("Done") { dismiss() }
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textFaint)
                TextField("Search the catalog", text: $query)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Button {
                createCustom()
            } label: {
                HStack(spacing: 8) {
                    Text("+").font(.system(size: 14, design: .monospaced))
                    Text(createLabel).font(.system(size: 13, weight: .semibold))
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
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var candidateEquipment: [Equipment] {
        allEquipment
            .filter { $0.isBuiltIn && !$0.inLibrary }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func exerciseSubtitle(_ exercise: Exercise) -> String {
        let equipment = exercise.equipment.map(\.name).sorted().joined(separator: ", ")
        return "\(exercise.muscleGroup.displayName) · \(equipment.isEmpty ? "Bodyweight" : equipment)"
    }

    private func catalogRow(name: String, sub: String, onAdd: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(sub).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            Button(action: onAdd) {
                Text("+ Add")
                    .font(.system(size: 11.5, weight: .bold))
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
                    .font(.system(size: 19, weight: .bold))
                Spacer()
                Text("BUILT-IN")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
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
                .font(.system(size: 10.5))
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


/// Identifiable wrapper so a prefilled editor can present via sheet(item:).
struct CustomExercisePrefill: Identifiable {
    let name: String
    var id: String { name }
}
