import SwiftUI
import SwiftData
import PlusPlusKit

/// Per-exercise planning sheet, v2 (#62): metric rows with steppers and
/// tap-to-wheel, superset structure actions, recent history, and delete.
/// Replaces the old inline MetricRows on the detail screen.
struct ExerciseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue

    let routine: Routine
    @Bindable var routineExercise: RoutineExercise
    let onAddToSuperset: (ExerciseGroup) -> Void

    /// Finished sessions, newest first, for the RECENT block.
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
           sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)])
    private var finishedSessions: [WorkoutSession]

    @State private var wheel: WheelTarget?
    @State private var showingRepsWheel = false

    private enum WheelTarget: String, Identifiable {
        case weight, duration
        var id: String { rawValue }
    }

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }
    private var exercise: Exercise? { routineExercise.exercise }
    private var group: ExerciseGroup? { routineExercise.group }
    private var isDuration: Bool { exercise?.exerciseType == .duration }

    private var groupIndex: Int? {
        guard let group else { return nil }
        return routine.sortedGroups.firstIndex(where: { $0 === group })
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.borderStrong)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(exercise?.name ?? "Unknown")
                        .font(.system(.title3, weight: .bold))
                        .padding(.top, 10)

                    HStack(spacing: 6) {
                        ChipLabel(exercise?.muscleGroup.displayName ?? "")
                        ChipLabel(equipmentText)
                    }
                    .padding(.top, 8)

                    metricsCard
                        .padding(.top, 12)

                    if group?.isSuperset == true {
                        HStack(spacing: 6) {
                            Image(systemName: "square.on.square")
                                .font(.system(.caption))
                                .foregroundStyle(Theme.textSecondary)
                            Text("Sets count applies to the whole superset — one round runs every exercise once.")
                                .font(.system(.caption))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.top, 6)
                    }

                    if let notes = exercise?.notes {
                        NotesBlock(notes)
                            .padding(.top, 13)
                    }

                    if !recentLines.isEmpty {
                        SheetSectionLabel("RECENT")
                            .padding(.top, 16)
                        VStack(spacing: 0) {
                            ForEach(recentLines, id: \.date) { line in
                                HStack {
                                    Text(line.date)
                                        .font(.system(.caption))
                                        .foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    Text(line.result)
                                        .font(.system(.caption, design: .monospaced))
                                }
                                .padding(.vertical, 6)
                                .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
                            }
                        }
                    }

                    structureActions
                        .padding(.top, 16)
                }
                .padding(.horizontal, 18)
            }

            Button {
                dismiss()
            } label: {
                Text("Close")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityIdentifier("closeExerciseSheet")
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .presentationBackground(Theme.surface)
        .sheet(item: $wheel) { target in
            switch target {
            case .weight:
                MetricWheelSheet(
                    metric: .weight,
                    weightUnit: weightUnit,
                    value: Binding(
                        get: { routineExercise.weight },
                        set: { routineExercise.weight = $0 }
                    )
                )
            case .duration:
                MetricWheelSheet(
                    metric: .duration,
                    weightUnit: weightUnit,
                    value: intMetricBinding(Binding(
                        get: { routineExercise.durationSeconds },
                        set: { routineExercise.durationSeconds = $0 }
                    ))
                )
            }
        }
        .sheet(isPresented: $showingRepsWheel) {
            RepTargetWheelSheet(
                target: RepTarget(lower: routineExercise.reps, upper: routineExercise.repsUpper)
            ) { newTarget in
                routineExercise.reps = newTarget.lower
                routineExercise.repsUpper = newTarget.upper
            }
        }
    }

    private var equipmentText: String {
        let names = exercise?.equipment.map(\.name).sorted() ?? []
        return names.isEmpty ? "Bodyweight" : names.joined(separator: ", ")
    }

    // MARK: - Metrics

    private var metricsCard: some View {
        VStack(spacing: 0) {
            if isDuration {
                MetricStepperRow(
                    label: "Duration",
                    value: durationText,
                    identifier: "duration",
                    onTapValue: { wheel = .duration },
                    onDecrement: { routineExercise.durationSeconds = step(.duration, routineExercise.durationSeconds, -1) },
                    onIncrement: { routineExercise.durationSeconds = step(.duration, routineExercise.durationSeconds, 1) }
                )
            } else {
                MetricStepperRow(
                    label: "Weight",
                    value: WorkoutMetric.weight.displayText(routineExercise.weight, weightUnit: weightUnit),
                    identifier: "weight",
                    onTapValue: { wheel = .weight },
                    onDecrement: { routineExercise.weight = WorkoutMetric.weight.decremented(routineExercise.weight, weightUnit: weightUnit, stepOverride: routineExercise.exercise?.weightStepOverride) },
                    onIncrement: { routineExercise.weight = WorkoutMetric.weight.incremented(routineExercise.weight, weightUnit: weightUnit, stepOverride: routineExercise.exercise?.weightStepOverride) }
                )
                MetricStepperRow(
                    label: "Reps",
                    value: RepTarget(lower: routineExercise.reps, upper: routineExercise.repsUpper).display,
                    identifier: "reps",
                    onTapValue: { showingRepsWheel = true },
                    onDecrement: { applyReps(RepTarget(lower: routineExercise.reps, upper: routineExercise.repsUpper).decremented()) },
                    onIncrement: { applyReps(RepTarget(lower: routineExercise.reps, upper: routineExercise.repsUpper).incremented()) }
                )
            }
            MetricStepperRow(
                label: "Sets",
                value: "\(group?.sets ?? 1)",
                identifier: "sets",
                onTapValue: nil,
                onDecrement: { group?.sets = max(1, (group?.sets ?? 1) - 1) },
                onIncrement: { group?.sets = min(20, (group?.sets ?? 1) + 1) }
            )
        }
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    private var durationText: String {
        guard let seconds = routineExercise.durationSeconds else { return "—" }
        return seconds >= 60
            ? WorkoutMetric.duration.formatted(Double(seconds))
            : "\(seconds)s"
    }

    private func step(_ metric: WorkoutMetric, _ value: Int?, _ direction: Double) -> Int {
        let stepped = direction > 0
            ? metric.incremented(value.map(Double.init))
            : metric.decremented(value.map(Double.init))
        return Int(stepped.rounded())
    }

    private func applyReps(_ target: RepTarget) {
        routineExercise.reps = target.lower
        routineExercise.repsUpper = target.upper
    }

    // MARK: - Recent

    private struct RecentLine {
        let date: String
        let result: String
    }

    private var recentLines: [RecentLine] {
        guard let name = exercise?.name else { return [] }
        var lines: [RecentLine] = []
        for session in finishedSessions.prefix(6) {
            let matches = session.sortedSetLogs.filter { $0.exerciseName == name && $0.completedAt != nil }
            guard !matches.isEmpty else { continue }
            let reps = matches.map { log in
                log.exerciseType == .duration
                    ? WorkoutMetric.duration.formatted(log.actualDuration.map(Double.init))
                    : "\(log.actualReps.map(String.init) ?? "—")"
            }.joined(separator: " · ")
            var result = reps
            if let weight = matches.first?.actualWeight, weight > 0 {
                result += " @ \(WorkoutMetric.weight.formatted(weight))\(weightUnit.symbol)"
            }
            lines.append(RecentLine(
                date: session.startedAt.formatted(.dateTime.month(.abbreviated).day()),
                result: result
            ))
            if lines.count == 3 { break }
        }
        return lines
    }

    // MARK: - Structure

    private var structureActions: some View {
        VStack(spacing: 7) {
            if let group, group.isSuperset {
                SheetActionButton("Move out of superset", systemImage: "square.on.square") {
                    routine.splitExercise(routineExercise, context: modelContext)
                    dismiss()
                }
            }
            if let group, !group.isSuperset, let index = groupIndex {
                if index > 0 {
                    SheetActionButton("Superset with exercise above", systemImage: "square.on.square") {
                        routine.mergeSoloGroup(group, direction: -1, context: modelContext)
                        dismiss()
                    }
                }
                if index < routine.sortedGroups.count - 1 {
                    SheetActionButton("Superset with exercise below", systemImage: "square.on.square") {
                        routine.mergeSoloGroup(group, direction: 1, context: modelContext)
                        dismiss()
                    }
                }
            }
            HStack(spacing: 7) {
                SheetActionButton("Move up", systemImage: "arrow.up", dimmed: groupIndex == 0) {
                    moveGroup(-1)
                }
                SheetActionButton("Move down", systemImage: "arrow.down", dimmed: groupIndex == routine.sortedGroups.count - 1) {
                    moveGroup(1)
                }
            }
            SheetActionButton("Delete exercise", destructive: true) {
                deleteExercise()
            }
        }
    }

    private func moveGroup(_ delta: Int) {
        guard let group, let index = groupIndex else { return }
        var sorted = routine.sortedGroups
        let target = index + delta
        guard sorted.indices.contains(target) else { return }
        sorted.swapAt(index, target)
        for (newOrder, moved) in sorted.enumerated() {
            moved.order = newOrder
        }
        _ = group
        dismiss()
    }

    private func deleteExercise() {
        let group = routineExercise.group
        modelContext.delete(routineExercise)
        if let group {
            group.reindexExercises()
            if group.sortedExercises.isEmpty {
                modelContext.delete(group)
                routine.reindexGroups()
            }
        }
        dismiss()
    }
}

// MARK: - Shared v2 sheet components

/// Small outlined chip ("Shoulders", "Resistance Band").
struct ChipLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(.caption2))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2.5)
            .overlay(Capsule().strokeBorder(Theme.borderStrong))
    }
}

/// Amber-left-border notes block (form cues).
struct NotesBlock: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Theme.notes)
                .frame(width: 2)
            Text(text)
                .font(.system(.footnote))
                .foregroundStyle(Theme.notes)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Single-wheel picker sheet for weight/duration/rest, v2 styling.
struct MetricWheelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let metric: WorkoutMetric
    var weightUnit: WeightUnit = .lb
    @Binding var value: Double?

    var body: some View {
        NavigationStack {
            Picker(metric.label, selection: Binding(
                get: { metric.nearestWheelValue(to: value, weightUnit: weightUnit) },
                set: { value = $0 }
            )) {
                ForEach(metric.wheelValues(weightUnit: weightUnit), id: \.self) { candidate in
                    Text(metric.displayText(candidate, weightUnit: weightUnit))
                        .font(.system(.body, design: .monospaced))
                        .tag(candidate)
                }
            }
            .pickerStyle(.wheel)
            .navigationTitle(metric.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationDetents([.height(300)])
        .presentationBackground(Theme.surface)
    }
}
