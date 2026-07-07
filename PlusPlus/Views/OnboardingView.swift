import SwiftUI
import SwiftData
import PlusPlusKit

/// Setup state for the timeline onboarding (Claude Design handoff 2,
/// "setup-as-timeline"): there is no onboarding flow anymore — a fresh
/// install's Today shows three setup steps as timeline entries, gated
/// bottom-up like commits. Equipment is the only step needing a stored
/// flag (its "done" can't be derived — the catalog defaults to
/// everything owned); routines and schedules are derived live.
enum SetupState {
    static let equipmentDoneKey = "setupEquipmentDone"
    static let equipmentDoneDateKey = "setupEquipmentDoneDate"

    static var equipmentDone: Bool {
        UserDefaults.standard.bool(forKey: equipmentDoneKey)
    }

    static func markEquipmentDone() {
        UserDefaults.standard.set(true, forKey: equipmentDoneKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: equipmentDoneDateKey)
    }

    static var equipmentDoneDate: Date? {
        let stamp = UserDefaults.standard.double(forKey: equipmentDoneDateKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }
}

/// The equipment-access picker as a standalone sheet — opened from the
/// Today setup timeline ("1 of 3") and from Settings → EQUIPMENT
/// ACCESS. Writes Equipment.inLibrary; only filters the catalog, never
/// touches history.
struct EquipmentAccessSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]

    var onDone: () -> Void = {}

    @State private var selected: Set<String> = []
    @State private var search = ""

    private var builtIns: [Equipment] {
        allEquipment.filter(\.isBuiltIn)
    }

    private var visibleEquipment: [Equipment] {
        builtIns.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    private struct Preset {
        let name: String
        let items: Set<String>
    }

    private var presets: [Preset] {
        let all = Set(builtIns.map(\.name))
        return [
            Preset(name: "Full gym", items: all),
            Preset(name: "Home basics", items: ["Dumbbells", "Bench", "Kettlebell", "Resistance Band", "Pull-Up Bar"]),
            Preset(name: "Bands only", items: ["Resistance Band"]),
            Preset(name: "Bodyweight", items: []),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "What do you have access to?", actionLabel: "Cancel", action: { dismiss() })

            Text("Filters the exercise catalog everywhere · never touches logged history")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 6)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(presets, id: \.name) { preset in
                    presetCard(preset)
                }
            }
            .padding(.top, 14)

            SearchField(prompt: "Search equipment", text: $search)
                .padding(.top, 12)

            ScrollView {
                FlowChips(
                    items: visibleEquipment.map(\.name),
                    isSelected: { selected.contains($0) },
                    toggle: { name in
                        if selected.contains(name) {
                            selected.remove(name)
                        } else {
                            selected.insert(name)
                        }
                    }
                )
                .padding(.vertical, 10)
            }

            Button {
                for equipment in builtIns {
                    equipment.inLibrary = selected.contains(equipment.name)
                }
                SetupState.markEquipmentDone()
                onDone()
                dismiss()
            } label: {
                Text(selected.isEmpty ? "Set equipment · bodyweight only" : "Set equipment · \(selected.count) item\(selected.count == 1 ? "" : "s")")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityIdentifier("setEquipmentButton")
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 20)
        .presentationBackground(Theme.background)
        .onAppear {
            selected = Set(builtIns.filter(\.inLibrary).map(\.name))
        }
    }

    private func presetCard(_ preset: Preset) -> some View {
        let active = selected == preset.items
        let count = preset.items.count
        // Accent-tinted when active: what you own is data, same
        // rationale as the schedule day circles.
        return Button {
            selected = preset.items
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(active ? Theme.accent : Theme.textPrimary)
                Text(count == 0 ? "just you" : "\(count) item\(count == 1 ? "" : "s")")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(active ? Theme.accent.opacity(0.75) : Theme.textFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(active ? Theme.accent.opacity(0.14) : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? Theme.accent.opacity(0.55) : Theme.border))
        }
    }
}

/// The first-routine seeder as a standalone sheet — the setup
/// timeline's "2 of 3". Dismissing without choosing leaves the step
/// pending; that IS the skip.
struct StarterSeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Build your first routine", actionLabel: "Cancel", action: { dismiss() })

            Text("You can change everything later — it's just a starting point")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 6)

            VStack(spacing: 8) {
                option(
                    title: "Starter push/pull split",
                    caption: "Two routines from the catalog, matched to your equipment"
                ) {
                    seedStarterSplit()
                    dismiss()
                }
                .accessibilityIdentifier("starterSplitButton")

                option(
                    title: "One empty routine",
                    caption: "A blank \"Routine A\" to build yourself"
                ) {
                    modelContext.insert(Routine(name: "Routine A", order: 0))
                    dismiss()
                }
            }
            .padding(.top, 16)

            Spacer()
        }
        .padding(.horizontal, 20)
        .presentationBackground(Theme.background)
        .presentationDetents([.medium])
    }

    private func option(title: String, caption: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(caption)
                    .font(.system(.footnote))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
        }
    }

    /// Two routines from the built-in catalog, equipment-aware: each
    /// slot takes its first owned candidate and is skipped outright when
    /// nothing fits, with bodyweight anchors guaranteeing neither
    /// routine comes out empty. 3×8–12 on lifts.
    private func seedStarterSplit() {
        let pushSlots = [
            ["Bench Press", "Incline Dumbbell Press", "Push-Up"],
            ["Overhead Press", "Lateral Raise"],
            ["Tricep Pushdown", "Overhead Tricep Extension"],
            ["Push-Up"],
        ]
        let pullSlots = [
            ["Barbell Row", "Cable Row", "Pull-Up"],
            ["Lat Pulldown", "Pull-Up"],
            ["Barbell Curl", "Dumbbell Curl"],
            ["Burpee"],
        ]
        seedRoutine(named: "Push Day", slots: pushSlots, order: 0)
        seedRoutine(named: "Pull Day", slots: pullSlots, order: 1)
    }

    private func seedRoutine(named name: String, slots: [[String]], order: Int) {
        let byName = Dictionary(uniqueKeysWithValues: allExercises.filter(\.isBuiltIn).map { ($0.name, $0) })
        let routine = Routine(name: name, order: order)
        modelContext.insert(routine)

        var used: Set<String> = []
        for slot in slots {
            guard let pick = slot.first(where: { candidate in
                guard !used.contains(candidate), let exercise = byName[candidate] else { return false }
                return ExerciseFilterState.missingEquipment(for: exercise).isEmpty
            }), let exercise = byName[pick] else { continue }
            used.insert(pick)
            exercise.inLibrary = true
            let group = routine.addExerciseInNewGroup(exercise, context: modelContext)
            if exercise.exerciseType == .weightReps, let entry = group.sortedExercises.first {
                entry.reps = 8
                entry.repsUpper = 12
            }
        }
    }
}

/// Minimal wrapping chip row used by the equipment picker.
struct FlowChips: View {
    let items: [String]
    let isSelected: (String) -> Bool
    let toggle: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 7)], spacing: 7) {
            ForEach(items, id: \.self) { name in
                let active = isSelected(name)
                Button {
                    toggle(name)
                } label: {
                    // Accent tint: ownership is data.
                    Text(name)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(active ? Theme.accent : Theme.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(active ? Theme.accent.opacity(0.16) : Theme.background, in: Capsule())
                        .overlay(Capsule().strokeBorder(active ? Theme.accent.opacity(0.55) : Theme.border))
                }
            }
        }
    }
}
