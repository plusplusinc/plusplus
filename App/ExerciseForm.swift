import DesignSystem
import SwiftUI
import WorkoutStore

/// The five settings a created exercise has, and no more: New exercise, pushed from Create, or
/// Customize, pushed from a created exercise's row in Exercises. Name, prefilled and not
/// focused, since the next thing to set is the muscle groups; Muscle groups and Equipment, each
/// one row reading what is checked ("Back, shoulders"; None and Bodyweight for none) that
/// opens its full list to check any number on (`Checklist`); Measure; and Per side. All checked
/// groups are equal. Everything else (its weight, plan, rest, and naming) is derived
/// (`Exercise(created:)`).
///
/// New exercise confirms with the host's word: Add where it goes into a routine, Create in
/// Exercises. It is off while the name is empty or already an exercise's
/// (`CreatedExercise.canAdd`), and after its first tap; no muscle group is needed. Cancel goes back
/// to the search
/// as it was; nothing is created before it.
///
/// Customize opens with the exercise as set, under the system back chevron, with no Cancel and
/// no Save: Muscle groups, Equipment, Measure, and Per side save as each changes, and the name
/// as its edit ends (Return, a tap elsewhere, or going back), never per keystroke. A name that
/// can't be saved (empty, or another exercise's) goes back to the stored one as its edit ends.
/// Below the settings, Used in reads how many routines have a row of it and opens their names
/// (`UsedInList`); last, Delete exercise, in red, asks first, with that count.
struct ExerciseForm: View {
    /// The exercise customized, or nil for a new one.
    let customizing: CreatedExercise?
    let exercises: ExerciseList
    /// What the confirm button reads.
    let confirmTitle: String
    /// The names of the routines that use the exercise customized, latest first.
    var usedIn: [String] = []
    let onConfirm: (CreatedExercise) async -> Void
    var onDelete: (() async -> Void)?

    @State private var name: String
    @State private var muscleGroups: Set<MuscleGroup>
    @State private var equipment: Set<Equipment>
    @State private var measure: Measure
    @State private var isPerSide: Bool
    /// In Customize, the exercise as last saved.
    @State private var stored: CreatedExercise?
    /// In Customize, the latest save, which the next one waits for so they land in order.
    @State private var lastSave: Task<Void, Never>?
    @State private var isConfirming = false
    @State private var isAskingToDelete = false
    @FocusState private var isNameFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss

    /// New exercise, named `name`, the search's text.
    init(
        name: String,
        exercises: ExerciseList,
        confirmTitle: String,
        onAdd: @escaping (CreatedExercise) async -> Void,
    ) {
        customizing = nil
        self.exercises = exercises
        self.confirmTitle = confirmTitle
        onConfirm = onAdd
        _name = State(initialValue: name)
        _muscleGroups = State(initialValue: [])
        _equipment = State(initialValue: [])
        _measure = State(initialValue: .reps)
        _isPerSide = State(initialValue: false)
    }

    /// Customize, for `exercise` as set; `onSave` takes each change as it is made.
    init(
        customizing exercise: CreatedExercise,
        exercises: ExerciseList,
        usedIn: [String],
        onSave: @escaping (CreatedExercise) async -> Void,
        onDelete: @escaping () async -> Void,
    ) {
        customizing = exercise
        self.exercises = exercises
        confirmTitle = ""
        self.usedIn = usedIn
        onConfirm = onSave
        self.onDelete = onDelete
        _stored = State(initialValue: exercise)
        _name = State(initialValue: exercise.name)
        _muscleGroups = State(initialValue: exercise.muscleGroups)
        _equipment = State(initialValue: exercise.equipment)
        _measure = State(initialValue: exercise.measure)
        _isPerSide = State(initialValue: exercise.isPerSide)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The new exercise as the form sets it now.
    private var edited: CreatedExercise {
        CreatedExercise(
            name: trimmedName,
            muscleGroups: muscleGroups,
            equipment: equipment,
            measure: measure,
            isPerSide: isPerSide,
        )
    }

    private var canConfirm: Bool {
        !isConfirming && CreatedExercise.canAdd(named: name, to: exercises)
    }

    /// `binding`, which in Customize also saves the exercise with each value it is set to. The
    /// save is made at the write, not from an `onChange`, which can skip a change.
    private func saving<Value>(
        _ binding: Binding<Value>,
        into keyPath: WritableKeyPath<CreatedExercise, Value>,
    ) -> Binding<Value> {
        guard customizing != nil else { return binding }
        return Binding {
            binding.wrappedValue
        } set: { value in
            binding.wrappedValue = value
            save { $0[keyPath: keyPath] = value }
        }
    }

    /// Saves the stored exercise with `change`, after any save still landing. Not once Delete is
    /// confirmed: a save then would put the exercise back.
    private func save(_ change: (inout CreatedExercise) -> Void) {
        guard var exercise = stored, !isConfirming else { return }
        change(&exercise)
        guard exercise != stored else { return }
        stored = exercise
        let previous = lastSave
        lastSave = Task {
            await previous?.value
            await onConfirm(exercise)
        }
    }

    /// Saves the name as its edit ends, or puts the stored one back if it can't be saved.
    private func endNameEdit() {
        guard let stored else { return }
        if CreatedExercise.canAdd(named: name, to: exercises, besides: stored.id) {
            name = trimmedName
            save { $0.name = trimmedName }
        } else {
            name = stored.name
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    nameField
                } label: {
                    // The field is labeled Name too; one VoiceOver stop reads both.
                    Text("Name").accessibilityHidden(true)
                }
            }
            .listRowBackground(Color.pp(.surface))
            Section {
                NavigationLink {
                    Checklist(
                        title: "Muscle groups",
                        items: MuscleGroup.allCases,
                        checked: saving($muscleGroups, into: \.muscleGroups),
                        name: \.name,
                    )
                } label: {
                    LabeledContent("Muscle groups", value: muscleGroups.line ?? "None")
                }
                NavigationLink {
                    Checklist(
                        title: "Equipment",
                        items: Equipment.allCases,
                        checked: saving($equipment, into: \.equipment),
                        name: \.name,
                    )
                } label: {
                    LabeledContent("Equipment", value: equipment.line ?? "Bodyweight")
                }
            }
            .listRowBackground(Color.pp(.surface))
            Section {
                Picker("Measure", selection: saving($measure, into: \.measure)) {
                    ForEach(Measure.allCases, id: \.self) { measure in
                        Text(measure.name).tag(measure)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.pp(.textSecondary))
                Toggle("Per side", isOn: saving($isPerSide, into: \.isPerSide))
            }
            .listRowBackground(Color.pp(.surface))
            if customizing != nil {
                usedInSection
                deleteSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.pp(.background))
        .navigationTitle(customizing == nil ? "New exercise" : "Customize")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(customizing == nil)
        .toolbar {
            if customizing == nil {
                ToolbarItem(placement: .cancellationAction) {
                    // Not once confirmed: the host pops the form when its save lands, and would
                    // pop whatever was pushed after it.
                    Button("Cancel") { dismiss() }
                        .disabled(isConfirming)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) { confirm() }
                        .disabled(!canConfirm)
                }
            }
        }
        .onChange(of: isNameFocused) { _, isFocused in
            if !isFocused {
                endNameEdit()
            }
        }
        // Going back, or pushing a list, ends the edit too, focus or not.
        .onDisappear { endNameEdit() }
    }

    private var usedInSection: some View {
        Section {
            if usedIn.isEmpty {
                LabeledContent("Used in", value: "No routines")
            } else {
                NavigationLink {
                    UsedInList(names: usedIn)
                } label: {
                    LabeledContent("Used in", value: Self.routineCount(usedIn.count))
                }
            }
        }
        .listRowBackground(Color.pp(.surface))
    }

    private var deleteSection: some View {
        Section {
            Button("Delete exercise", role: .destructive) {
                isAskingToDelete = true
            }
            .frame(maxWidth: .infinity)
            .disabled(isConfirming)
            // On the button, so the question comes out of it: on a screen pushed inside a
            // stack, iOS shows it as a popover, and attached to the form it pointed at the
            // form's middle.
            .confirmationDialog(
                "Delete \(customizing?.name ?? "")?",
                isPresented: $isAskingToDelete,
                titleVisibility: .visible,
            ) {
                Button("Delete exercise", role: .destructive) {
                    isConfirming = true
                    Task { await onDelete?() }
                }
            } message: {
                Text(deleteMessage)
            }
        }
        .listRowBackground(Color.pp(.surface))
    }

    /// The count, not the names: Used in has those.
    private var deleteMessage: String {
        let routines = switch usedIn.count {
        case 0: String(localized: "No routine uses it.")
        case 1: String(localized: "It will be removed from the routine that uses it.")
        default: String(
                localized: "It will be removed from the \(usedIn.count) routines that use it.",
            )
        }
        return routines + " " + String(localized: "Deleting doesn’t affect your workout history.")
    }

    static func routineCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 routine") : String(localized: "\(count) routines")
    }

    /// One line, trailing, at the usual sizes. At the accessibility sizes the label sits above
    /// the value, and one line would cut a typed name short, so it wraps, leading. Return ends
    /// the editing rather than starting a line.
    private var nameField: some View {
        let wraps = typeSize.isAccessibilitySize
        let oneLine = Binding {
            name
        } set: { typed in
            if typed.contains(where: \.isNewline) {
                name = typed.filter { !$0.isNewline }
                isNameFocused = false
            } else {
                name = typed
            }
        }
        return TextField("Name", text: oneLine, axis: wraps ? .vertical : .horizontal)
            .multilineTextAlignment(wraps ? .leading : .trailing)
            .submitLabel(.done)
            .focused($isNameFocused)
            // A field that wraps takes no label from its title.
            .accessibilityLabel("Name")
            .accessibilityIdentifier("newExercise.name")
    }

    private func confirm() {
        guard canConfirm else { return }
        isConfirming = true
        let exercise = edited
        Task { await onConfirm(exercise) }
    }
}

/// The routines a created exercise is used in, by name, the latest opened or edited first,
/// pushed from its Customize form's Used in. Names only: nothing here opens.
struct UsedInList: View {
    let names: [String]

    var body: some View {
        Form {
            Section {
                ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                    Text(name)
                }
            } footer: {
                Text("Most recently used first.")
            }
            .listRowBackground(Color.pp(.surface))
        }
        .scrollContentBackground(.hidden)
        .background(Color.pp(.background))
        .navigationTitle("Used in")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("New") {
    NavigationStack {
        ExerciseForm(
            name: "Ring row with rotation",
            exercises: .builtIn,
            confirmTitle: "Add",
        ) { _ in }
    }
}

#Preview("Customize") {
    NavigationStack {
        ExerciseForm(
            customizing: CreatedExercise(name: "Ring row with rotation", muscleGroups: [.back]),
            exercises: .builtIn,
            usedIn: ["PT day A", "Total body"],
            onSave: { _ in },
            onDelete: { },
        )
    }
}
