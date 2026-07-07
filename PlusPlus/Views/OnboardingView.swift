import SwiftUI
import SwiftData
import PlusPlusKit

/// First-run onboarding (#113, Claude Design v3 §6): two beats, both
/// skippable, quiet-terminal voice, no confetti. Beat 1 sets equipment
/// access (writes Equipment.inLibrary — it only filters the catalog and
/// never touches history); beat 2 optionally seeds a starter split.
/// Re-runnable from Settings → EQUIPMENT ACCESS.
struct OnboardingView: View {
    static let completedKey = "onboardingComplete"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(Self.completedKey) private var completed = false
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    /// Re-run mode (from Settings) skips beat 2 — a returning user
    /// doesn't want another starter workout.
    var isRerun = false

    private enum Beat {
        case equipment, starter
    }

    @State private var beat: Beat = .equipment
    @State private var selected: Set<String> = []
    @State private var search = ""

    private var builtIns: [Equipment] {
        allEquipment.filter(\.isBuiltIn)
    }

    private var visibleEquipment: [Equipment] {
        builtIns.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch beat {
            case .equipment: equipmentBeat
            case .starter: starterBeat
            }
        }
        .padding(.horizontal, 20)
        .background(Theme.background)
        .onAppear {
            selected = Set(builtIns.filter(\.inLibrary).map(\.name))
        }
        .interactiveDismissDisabled(!isRerun)
    }

    // MARK: - Beat 1: equipment access

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

    private var equipmentBeat: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderGlyph()
                .padding(.top, 18)
            Text("What do you have access to?")
                .font(.system(.title2, weight: .bold))
                .padding(.top, 12)
            Text("filters the exercise catalog everywhere · never touches logged history")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 4)

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
                applyEquipment()
                advance()
            } label: {
                Text(continueLabel)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityIdentifier("onboardingContinue")

            Button {
                advance()
            } label: {
                Text("skip — set later in Settings")
                    .font(.system(.footnote))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }

    private var continueLabel: String {
        selected.isEmpty ? "Continue · bodyweight only" : "Continue · \(selected.count) item\(selected.count == 1 ? "" : "s")"
    }

    private func presetCard(_ preset: Preset) -> some View {
        let active = selected == preset.items
        let count = preset.items.count
        // Accent-tinted when active: what you own is data (it drives the
        // catalog filter), same rationale as the schedule day circles —
        // and surface-vs-surfaceRaised was unreadably subtle (Dave,
        // build 10).
        return Button {
            selected = preset.items
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(active ? Theme.accent : Theme.textPrimary)
                Text(count == 0 ? "just you" : "\(count) item\(count == 1 ? "" : "s")")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(active ? Theme.accent.opacity(0.75) : Theme.textFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(active ? Theme.accent.opacity(0.14) : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? Theme.accent.opacity(0.55) : Theme.border))
        }
    }

    private func applyEquipment() {
        for equipment in builtIns {
            equipment.inLibrary = selected.contains(equipment.name)
        }
    }

    private func advance() {
        if isRerun {
            completed = true
            dismiss()
        } else {
            beat = .starter
        }
    }

    // MARK: - Beat 2: starter workout

    private var starterBeat: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderGlyph()
                .padding(.top, 18)
            Text("Seed a first workout?")
                .font(.system(.title2, weight: .bold))
                .padding(.top, 12)
            Text("you can change everything later — it's just a starting point")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 4)

            VStack(spacing: 8) {
                starterOption(
                    title: "Starter push/pull split",
                    caption: "two workouts from the catalog, matched to your equipment"
                ) {
                    seedStarterSplit()
                    finish()
                }
                .accessibilityIdentifier("starterSplitButton")

                starterOption(
                    title: "One empty workout",
                    caption: "a blank \"Workout A\" to build yourself"
                ) {
                    let workout = Workout(name: "Workout A", order: 0)
                    modelContext.insert(workout)
                    finish()
                }
            }
            .padding(.top, 16)

            Spacer()

            Button {
                finish()
            } label: {
                Text("skip — start blank")
                    .font(.system(.footnote))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 14)
            .accessibilityIdentifier("onboardingSkipStarter")
        }
    }

    private func starterOption(title: String, caption: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(caption)
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
        }
    }

    /// Two workouts from the built-in catalog, equipment-aware: each
    /// slot takes its first owned candidate and is skipped outright when
    /// nothing fits, with bodyweight anchors guaranteeing neither
    /// workout comes out empty. 3×8–12 on lifts.
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
        seedWorkout(named: "Push Day", slots: pushSlots, order: 0)
        seedWorkout(named: "Pull Day", slots: pullSlots, order: 1)
    }

    private func seedWorkout(named name: String, slots: [[String]], order: Int) {
        let byName = Dictionary(uniqueKeysWithValues: allExercises.filter(\.isBuiltIn).map { ($0.name, $0) })
        let workout = Workout(name: name, order: order)
        modelContext.insert(workout)

        var used: Set<String> = []
        for slot in slots {
            guard let pick = slot.first(where: { candidate in
                guard !used.contains(candidate), let exercise = byName[candidate] else { return false }
                return ExerciseFilterState.missingEquipment(for: exercise).isEmpty
            }), let exercise = byName[pick] else { continue }
            used.insert(pick)
            exercise.inLibrary = true
            let group = workout.addExerciseInNewGroup(exercise, context: modelContext)
            if exercise.exerciseType == .weightReps, let entry = group.sortedExercises.first {
                entry.reps = 8
                entry.repsUpper = 12
            }
        }
    }

    private func finish() {
        completed = true
        dismiss()
    }
}

/// Minimal wrapping chip row used by onboarding's equipment picker.
private struct FlowChips: View {
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
                    // Accent tint, not primaryFill: ownership is data
                    // (see the schedule day circles), and cream-vs-
                    // outline read as ambiguous on device.
                    Text(name)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(active ? Theme.accent : Theme.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(active ? Theme.accent.opacity(0.16) : Theme.background, in: Capsule())
                        .overlay(Capsule().strokeBorder(active ? Theme.accent.opacity(0.55) : Theme.border))
                }
            }
        }
    }
}
