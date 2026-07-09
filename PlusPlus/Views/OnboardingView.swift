import SwiftUI
import SwiftData
import PlusPlusKit

/// Setup state for the timeline onboarding (Claude Design handoff 2,
/// "setup-as-timeline"): there is no onboarding flow anymore — a fresh
/// install's Today shows three setup steps as timeline entries, gated
/// bottom-up like commits. Equipment is the only step needing a stored
/// flag (its "done" can't be derived — owning nothing is a valid
/// choice, #232); routines and schedules are derived live.
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

    // The populate offer rides Today, not the catalog (#204): Done just
    // raises this flag and dismisses; Today consumes it and asks from an
    // anchored alert. One-shot; the count is computed at ask time.
    static let populateOfferPendingKey = "setupPopulateOfferPending"

    static func requestPopulateOffer() {
        UserDefaults.standard.set(true, forKey: populateOfferPendingKey)
    }

    /// Returns whether an offer was pending, clearing it either way.
    static func consumePopulateOffer() -> Bool {
        let pending = UserDefaults.standard.bool(forKey: populateOfferPendingKey)
        UserDefaults.standard.removeObject(forKey: populateOfferPendingKey)
        return pending
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
            SheetHeader(title: "Starter routines", closeOnly: true, action: { dismiss() })

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

