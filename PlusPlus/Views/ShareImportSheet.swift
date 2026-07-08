import SwiftUI
import SwiftData
import PlusPlusKit

/// A decoded share link waiting for the user's yes/no. Identifiable so
/// sheet(item:) presents a fresh preview per link.
struct ShareImport: Identifiable {
    let id = UUID()
    let payload: RoutineShareLink.Payload
}

/// Preview of a routine somebody shared (#145): what's inside, what
/// will be created, what would be replaced — then one tap to import
/// through the normal interchange pipeline. Dismissing is the "no".
struct ShareImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Routine.name) private var routines: [Routine]
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    let payload: RoutineShareLink.Payload

    @State private var importError: String?

    private var routine: RoutineDTO { payload.routine }
    private var senderUnit: WeightUnit { payload.units ?? .lb }

    private var exerciseCount: Int {
        routine.groups.reduce(0) { $0 + $1.exercises.count }
    }

    /// Exercises the receiver doesn't have yet — created on import.
    private var newExerciseNames: [String] {
        let existing = Set(allExercises.map { $0.name.lowercased() })
        return payload.exercises.map(\.name).filter { !existing.contains($0.lowercased()) }
    }

    private var replacesExisting: Bool {
        routines.contains { $0.name.lowercased() == routine.name.lowercased() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: "Add routine",
                subtitle: routine.name,
                actionLabel: replacesExisting ? "Replace" : "Add",
                actionIdentifier: "importSharedRoutineButton",
                onCancel: { dismiss() },
                action: { importRoutine() }
            )

            Text("Someone sent you this — it came inside the link itself, nothing was uploaded.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(routine.name)
                        .font(.system(.title2, weight: .bold))
                        .padding(.top, 16)
                    Text(metaLine)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 3)
                    if let notes = routine.notes {
                        Text(notes)
                            .font(.system(.footnote))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 6)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(routine.groups.enumerated()), id: \.offset) { groupIndex, group in
                            groupBlock(group, index: groupIndex)
                        }
                    }
                    .padding(.top, 12)

                    if !newExerciseNames.isEmpty {
                        Text("Adds \(newExerciseNames.count) exercise\(newExerciseNames.count == 1 ? "" : "s") you don't have yet: \(newExerciseNames.joined(separator: ", "))")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 12)
                    }
                    if replacesExisting {
                        Text("You already have a routine named \"\(routine.name)\" — importing replaces its plan. Logged history is untouched.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.notes)
                            .padding(.top, 8)
                    }
                    if let importError {
                        Text(importError)
                            .font(.system(.caption))
                            .foregroundStyle(Theme.destructive)
                            .padding(.top, 8)
                    }
                }
                .padding(.bottom, 16)
            }

        }
        .padding(.horizontal, 18)
        .presentationBackground(Theme.background)
    }

    private var metaLine: String {
        var parts = ["\(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s")", "rest \(routine.restSeconds)s"]
        if payload.units != nil {
            parts.append(senderUnit.rawValue)
        }
        return parts.joined(separator: " · ")
    }

    private func groupBlock(_ group: RoutineDTO.GroupDTO, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("\(group.sets) SET\(group.sets == 1 ? "" : "S")")
                + Text(group.exercises.count > 1 ? " · " : "")
                + (group.exercises.count > 1
                    ? (Text(Image(systemName: "square.on.square")) + Text(" SUPERSET")).foregroundStyle(Theme.textSecondary)
                    : Text("")))
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .kerning(0.7)
                .padding(.top, index == 0 ? 4 : 12)

            ForEach(Array(group.exercises.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 8) {
                    Text(entry.exercise)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(targetText(entry, sets: group.sets))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 5)
            }
        }
    }

    private func targetText(_ entry: RoutineDTO.EntryDTO, sets: Int) -> String {
        let def = payload.exercises.first { $0.name.lowercased() == entry.exercise.lowercased() }
        if def?.exerciseType == .duration {
            return "\(sets)× " + WorkoutMetric.duration.displayText(entry.durationSeconds.map(Double.init))
        }
        var text = "\(sets)×\(RepTarget(lower: entry.reps, upper: entry.repsUpper).display)"
        if let weight = entry.weight, weight > 0 {
            text += " @ " + WorkoutMetric.weight.displayText(weight, weightUnit: senderUnit)
        }
        return text
    }

    private func importRoutine() {
        let bundle = ExportBundle(
            units: payload.units,
            exercises: payload.exercises,
            routines: [payload.routine],
            sessions: []
        )
        do {
            try InterchangeMapping.importBundle(bundle, context: modelContext)
            dismiss()
        } catch {
            importError = "Import failed: \(error.localizedDescription)"
        }
    }
}
