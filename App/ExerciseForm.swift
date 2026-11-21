import DesignSystem
import SwiftUI
import WorkoutStore

/// Customize, an exercise's five settings, and no more, pushed from a routine row's Customize…
/// in its sheet (the sheet a created exercise's row opens on after Create), or from Customize…
/// in a row's hold menu in Add exercise. Name, not focused, since the next thing to set is the
/// muscle groups; Muscle groups and Equipment, each one row reading what is checked ("Back,
/// shoulders"; None and Bodyweight for none) that opens its full list to check any number on
/// (`Checklist`); Measure; and Per side. All checked groups are equal; none is needed. Everything
/// else (its weight, plan, rest, and naming) is derived (`Exercise(created:)`), or for a built-in
/// shipped (`Exercise(builtIn:customized:)`).
///
/// It opens with the exercise as set, under the system back chevron, with no Cancel and no
/// Save: Muscle groups, Equipment, Measure, and Per side save as each changes, and the name
/// as its edit ends (Return, a tap elsewhere, or going back), never per keystroke. A name that
/// can't be saved (empty, or another exercise's) goes back to the stored one as its edit ends.
/// Below the settings, Used in reads how many routines have a row of it and opens their names
/// (`UsedInList`); last, Delete exercise, in red, asks first, with that count, naming the open
/// routine first when it uses the exercise (`DeleteQuestion`); confirmed, the form stays as it
/// is while what shows it closes, and its host shows the delete in beats
/// (`WorkoutScreen.deleteExercise(_:closing:)`). A built-in's
/// form ends instead in Clear customizations, red, disabled while nothing differs from how it
/// shipped; it asks first, listing what changed, and puts the form back as shipped. Both ask in
/// a centered alert, with Cancel. There is no footer: what changed shows only in Clear's
/// question.
struct ExerciseForm: View {
    /// What the form ends in: Delete exercise for one someone created, Clear customizations for
    /// a built-in, with the settings it shipped with. Delete's question names the open routine
    /// first when it uses the exercise (`DeleteQuestion`).
    enum Ending {
        case delete(usedByOpenWorkout: Bool, () async -> Void)
        case clear(original: ExerciseSettings, () async -> Void)
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
    @State private var isAskingToClear = false
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
        guard !isDeleting else { return }
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
            Section {
                Picker("Measure", selection: saving(\.measure)) {
                    ForEach(Measure.allCases, id: \.self) { measure in
                        Text(measure.name).tag(measure)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.pp(.textSecondary))
                Toggle("Per side", isOn: saving(\.isPerSide))
            }
            .listRowBackground(Color.pp(.surface))
            usedInSection
            switch ending {
            case let .delete(usedByOpen, onDelete):
                deleteSection(usedByOpenWorkout: usedByOpen, onDelete)
            case let .clear(original, onClear): clearSection(original, onClear)
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
                LabeledContent("Used in", value: "No workouts")
            } else {
                NavigationLink {
                    UsedInList(names: usedIn)
                } label: {
                    LabeledContent("Used in", value: Self.workoutCount(usedIn.count))
                }
            }
        }
        .listRowBackground(Color.pp(.surface))
    }

    /// Red, as Delete is; nothing to clear while the settings are as they shipped. It asks
    /// first, saying what changed; confirmed, the form reads as shipped.
    private func clearSection(
        _ original: ExerciseSettings,
        _ onClear: @escaping () async -> Void,
    ) -> some View {
        Section {
            Button("Clear customizations", role: .destructive) {
                isAskingToClear = true
            }
            .frame(maxWidth: .infinity)
            .disabled(stored == original)
            // A centered alert, as Delete's is.
            .alert(
                "Clear your customizations to \(original.name)?",
                isPresented: $isAskingToClear,
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Clear customizations", role: .destructive) {
                    // At once, so a change made while the clear lands builds on what shipped.
                    stored = original
                    name = original.name
                    let previous = lastSave
                    lastSave = Task {
                        await previous?.value
                        await onClear()
                    }
                }
            } message: {
                Text(Self.clearMessage(stored, from: original))
            }
        }
        .listRowBackground(Color.pp(.surface))
    }

    /// What changed, then that the routines' numbers stay: Clear's question.
    private static func clearMessage(
        _ stored: ExerciseSettings,
        from original: ExerciseSettings,
    ) -> String {
        let changes = stored.changes(from: original).joined(separator: ", ")
        return String(localized: "Changed from the original: \(changes).") + " "
            + String(localized: "Sets, reps, and weights in your workouts stay.")
    }

    private func deleteSection(
        usedByOpenWorkout: Bool,
        _ onDelete: @escaping () async -> Void,
    ) -> some View {
        Section {
            Button("Delete exercise", role: .destructive) {
                isAskingToDelete = true
            }
            .frame(maxWidth: .infinity)
            // Not disabled: dimmed, it grayed out on the form as the sheet went down with it.
            .allowsHitTesting(!isDeleting)
            // A centered alert, not a dialog anchored to the button (decided 2026-11-17).
            .alert("Delete \(stored.name)?", isPresented: $isAskingToDelete) {
                Button("Cancel", role: .cancel) { }
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
                Text(DeleteQuestion.message(
                    workoutCount: usedIn.count,
                    usedByOpenWorkout: usedByOpenWorkout,
                ))
            }
        }
        .listRowBackground(Color.pp(.surface))
    }

    static func workoutCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 workout") : String(localized: "\(count) workouts")
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
            ending: .delete(usedByOpenWorkout: true) { },
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
            ending: .clear(original: bench) { },
        )
    }
}
