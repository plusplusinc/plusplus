import DesignSystem
import SwiftUI
import WorkoutStore

/// Customize, the five settings a created exercise has, and no more, pushed from a created
/// exercise's row in Exercises, or by Create, in Exercises or Add exercise, once it has stored the
/// exercise. Name, not focused, since the next thing to set is the muscle groups; Muscle groups
/// and Equipment, each one row reading what is checked ("Back, shoulders"; None and Bodyweight
/// for none) that opens its full list to check any number on (`Checklist`); Measure; and Per
/// side. All checked groups are equal; none is needed. Everything else (its weight, plan, rest,
/// and naming) is derived (`Exercise(created:)`).
///
/// It opens with the exercise as set, under the system back chevron, with no Cancel and no
/// Save: Muscle groups, Equipment, Measure, and Per side save as each changes, and the name
/// as its edit ends (Return, a tap elsewhere, or going back), never per keystroke. A name that
/// can't be saved (empty, or another exercise's) goes back to the stored one as its edit ends.
/// Below the settings, Used in reads how many routines have a row of it and opens their names
/// (`UsedInList`); last, Delete exercise, in red, asks first, with that count.
struct ExerciseForm: View {
    /// What the form ends in: Delete exercise for one someone created, Clear customizations for
    /// a built-in, with the settings it shipped with.
    enum Ending {
        case delete(() async -> Void)
        case clear(original: ExerciseSettings)
    }

    /// The exercise customized, which its name may stay the name of.
    let id: Exercise.ID
    let exercises: ExerciseList
    /// The names of the routines that use the exercise customized, latest first.
    let usedIn: [String]
    /// Takes each change as it is made.
    let onSave: (ExerciseSettings) async -> Void
    let ending: Ending

    @State private var name: String
    /// The exercise as last saved, which every setting but the name reads: those save as they
    /// change, and the name only as its edit ends.
    @State private var stored: ExerciseSettings
    /// The latest save, which the next one waits for so they land in order.
    @State private var lastSave: Task<Void, Never>?
    @State private var isDeleting = false
    @State private var isAskingToDelete = false
    @FocusState private var isNameFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    init(
        customizing id: Exercise.ID,
        settings: ExerciseSettings,
        exercises: ExerciseList,
        usedIn: [String],
        onSave: @escaping (ExerciseSettings) async -> Void,
        ending: Ending,
    ) {
        self.id = id
        self.exercises = exercises
        self.usedIn = usedIn
        self.onSave = onSave
        self.ending = ending
        _stored = State(initialValue: settings)
        _name = State(initialValue: settings.name)
    }

    /// A built-in's settings, which nothing stores yet, so they don't take a change.
    private var isLocked: Bool {
        if case .clear = ending {
            true
        } else {
            false
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The stored exercise's setting at `keyPath`, saving the exercise with each value it is set
    /// to. The save is made at the write, not from an `onChange`, which can skip a change.
    private func saving<Value>(
        _ keyPath: WritableKeyPath<ExerciseSettings, Value>,
    ) -> Binding<Value> {
        Binding {
            stored[keyPath: keyPath]
        } set: { value in
            save { $0[keyPath: keyPath] = value }
        }
    }

    /// Saves the stored exercise with `change`, after any save still landing. Not once Delete is
    /// confirmed: a save then would put the exercise back.
    private func save(_ change: (inout ExerciseSettings) -> Void) {
        guard !isDeleting, !isLocked else { return }
        var exercise = stored
        change(&exercise)
        guard exercise != stored else { return }
        stored = exercise
        let previous = lastSave
        lastSave = Task {
            await previous?.value
            await onSave(exercise)
        }
    }

    /// Saves the name as its edit ends, or puts the stored one back if it can't be saved.
    private func endNameEdit() {
        if CreatedExercise.canAdd(named: name, to: exercises, besides: id) {
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
            .disabled(isLocked)
            Section {
                NavigationLink {
                    Checklist(
                        title: "Muscle groups",
                        items: MuscleGroup.allCases,
                        checked: saving(\.muscleGroups),
                        name: \.name,
                    )
                } label: {
                    LabeledContent("Muscle groups", value: stored.muscleGroups.line ?? "None")
                }
                NavigationLink {
                    Checklist(
                        title: "Equipment",
                        items: Equipment.allCases,
                        checked: saving(\.equipment),
                        name: \.name,
                    )
                } label: {
                    LabeledContent("Equipment", value: stored.equipment.line ?? "Bodyweight")
                }
            }
            .listRowBackground(Color.pp(.surface))
            .disabled(isLocked)
            Section {
                Picker("Measure", selection: saving(\.measure)) {
                    ForEach(Measure.allCases, id: \.self) { measure in
                        Text(measure.name).tag(measure)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.pp(.textSecondary))
                Toggle("Per side", isOn: saving(\.isPerSide))
            } footer: {
                if case .clear = ending {
                    Text("Built in.")
                }
            }
            .listRowBackground(Color.pp(.surface))
            .disabled(isLocked)
            usedInSection
            switch ending {
            case let .delete(onDelete): deleteSection(onDelete)
            case let .clear(original): clearSection(original)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.pp(.background))
        .navigationTitle("Customize")
        .navigationBarTitleDisplayMode(.inline)
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

    /// Red, as Delete is; nothing to clear yet while the settings are as they shipped.
    private func clearSection(_ original: ExerciseSettings) -> some View {
        Section {
            Button("Clear customizations", role: .destructive) { }
                .frame(maxWidth: .infinity)
                .disabled(stored == original)
        }
        .listRowBackground(Color.pp(.surface))
    }

    private func deleteSection(_ onDelete: @escaping () async -> Void) -> some View {
        Section {
            Button("Delete exercise", role: .destructive) {
                isAskingToDelete = true
            }
            .frame(maxWidth: .infinity)
            .disabled(isDeleting)
            // On the button, so the question comes out of it: on a screen pushed inside a
            // stack, iOS shows it as a popover, and attached to the form it pointed at the
            // form's middle.
            .confirmationDialog(
                "Delete \(stored.name)?",
                isPresented: $isAskingToDelete,
                titleVisibility: .visible,
            ) {
                Button("Delete exercise", role: .destructive) {
                    isDeleting = true
                    // After any save still landing: the session takes one exercise change at
                    // a time and drops one that comes in meanwhile.
                    let previous = lastSave
                    Task {
                        await previous?.value
                        await onDelete()
                    }
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
            .accessibilityIdentifier("customize.name")
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

#Preview {
    NavigationStack {
        ExerciseForm(
            customizing: "created:preview",
            settings: ExerciseSettings(name: "Ring row with rotation", muscleGroups: [.back]),
            exercises: .builtIn,
            usedIn: ["PT day A", "Total body"],
            onSave: { _ in },
            ending: .delete { },
        )
    }
}

#Preview("Built in") {
    let bench = ExerciseSettings(name: "Barbell bench press", muscleGroups: [.chest])
    NavigationStack {
        ExerciseForm(
            customizing: "barbell-bench-press",
            settings: bench,
            exercises: .builtIn,
            usedIn: ["Push day"],
            onSave: { _ in },
            ending: .clear(original: bench),
        )
    }
}
