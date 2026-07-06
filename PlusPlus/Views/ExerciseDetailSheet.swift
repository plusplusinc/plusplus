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

    let workout: Workout
    @Bindable var workoutExercise: WorkoutExercise
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
    private var exercise: Exercise? { workoutExercise.exercise }
    private var group: ExerciseGroup? { workoutExercise.group }
    private var isDuration: Bool { exercise?.exerciseType == .duration }

    private var groupIndex: Int? {
        guard let group else { return nil }
        return workout.sortedGroups.firstIndex(where: { $0 === group })
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
                        .font(.system(size: 19, weight: .bold))
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
                            Text("⧉")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.superset)
                            Text("Sets count applies to the whole superset — one round runs every exercise once.")
                                .font(.system(size: 11))
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
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    Text(line.result)
                                        .font(.system(size: 11, design: .monospaced))
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
                    .font(.system(size: 14, weight: .bold))
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
                        get: { workoutExercise.weight },
                        set: { workoutExercise.weight = $0 }
                    )
                )
            case .duration:
                MetricWheelSheet(
                    metric: .duration,
                    weightUnit: weightUnit,
                    value: intMetricBinding(Binding(
                        get: { workoutExercise.durationSeconds },
                        set: { workoutExercise.durationSeconds = $0 }
                    ))
                )
            }
        }
        .sheet(isPresented: $showingRepsWheel) {
            RepTargetWheelSheet(
                target: RepTarget(lower: workoutExercise.reps, upper: workoutExercise.repsUpper)
            ) { newTarget in
                workoutExercise.reps = newTarget.lower
                workoutExercise.repsUpper = newTarget.upper
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
                    onDecrement: { workoutExercise.durationSeconds = step(.duration, workoutExercise.durationSeconds, -1) },
                    onIncrement: { workoutExercise.durationSeconds = step(.duration, workoutExercise.durationSeconds, 1) }
                )
            } else {
                MetricStepperRow(
                    label: "Weight",
                    value: WorkoutMetric.weight.displayText(workoutExercise.weight, weightUnit: weightUnit),
                    identifier: "weight",
                    onTapValue: { wheel = .weight },
                    onDecrement: { workoutExercise.weight = WorkoutMetric.weight.decremented(workoutExercise.weight, weightUnit: weightUnit) },
                    onIncrement: { workoutExercise.weight = WorkoutMetric.weight.incremented(workoutExercise.weight, weightUnit: weightUnit) }
                )
                MetricStepperRow(
                    label: "Reps",
                    value: RepTarget(lower: workoutExercise.reps, upper: workoutExercise.repsUpper).display,
                    identifier: "reps",
                    onTapValue: { showingRepsWheel = true },
                    onDecrement: { applyReps(RepTarget(lower: workoutExercise.reps, upper: workoutExercise.repsUpper).decremented()) },
                    onIncrement: { applyReps(RepTarget(lower: workoutExercise.reps, upper: workoutExercise.repsUpper).incremented()) }
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
        guard let seconds = workoutExercise.durationSeconds else { return "—" }
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
        workoutExercise.reps = target.lower
        workoutExercise.repsUpper = target.upper
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
                SheetActionButton("⧉ Move out of superset") {
                    workout.splitExercise(workoutExercise, context: modelContext)
                    dismiss()
                }
            }
            if let group, !group.isSuperset, let index = groupIndex {
                if index > 0 {
                    SheetActionButton("⧉ Superset with exercise above") {
                        workout.mergeSoloGroup(group, direction: -1, context: modelContext)
                        dismiss()
                    }
                }
                if index < workout.sortedGroups.count - 1 {
                    SheetActionButton("⧉ Superset with exercise below") {
                        workout.mergeSoloGroup(group, direction: 1, context: modelContext)
                        dismiss()
                    }
                }
            }
            HStack(spacing: 7) {
                SheetActionButton("↑ Move up", dimmed: groupIndex == 0) {
                    moveGroup(-1)
                }
                SheetActionButton("↓ Move down", dimmed: groupIndex == workout.sortedGroups.count - 1) {
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
        var sorted = workout.sortedGroups
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
        let group = workoutExercise.group
        modelContext.delete(workoutExercise)
        if let group {
            group.reindexExercises()
            if group.sortedExercises.isEmpty {
                modelContext.delete(group)
                workout.reindexGroups()
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
            .font(.system(size: 10))
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
                .font(.system(size: 12))
                .foregroundStyle(Theme.notes)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Metric row in the v2 sheet style: label, tappable mono value, and a
/// bordered −/+ pair. Increment/decrement identifiers are derived from
/// `identifier` ("weightIncrement" etc.) for the UI tests.
struct MetricStepperRow: View {
    let label: String
    let value: String
    let identifier: String
    var onTapValue: (() -> Void)?
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                onTapValue?()
            } label: {
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
            }
            .disabled(onTapValue == nil)
            .accessibilityIdentifier("\(identifier)Value")

            HStack(spacing: 0) {
                Button(action: onDecrement) {
                    Text("−")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 42, height: 28)
                }
                .accessibilityIdentifier("\(identifier)Decrement")
                Divider().frame(height: 28).overlay(Theme.border)
                Button(action: onIncrement) {
                    Text("+")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 42, height: 28)
                }
                .accessibilityIdentifier("\(identifier)Increment")
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
    }
}

/// Bordered full-width action button used in v2 sheets.
struct SheetActionButton: View {
    let title: String
    var destructive = false
    var dimmed = false
    let action: () -> Void

    init(_ title: String, destructive: Bool = false, dimmed: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.destructive = destructive
        self.dimmed = dimmed
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(destructive ? Theme.destructive : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(destructive ? Theme.destructive.opacity(0.4) : Theme.borderStrong)
                )
        }
        .opacity(dimmed ? 0.35 : 1)
        .disabled(dimmed)
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
                        .font(.system(size: 17, design: .monospaced))
                        .tag(candidate)
                }
            }
            .pickerStyle(.wheel)
            .navigationTitle(metric.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationDetents([.height(300)])
        .presentationBackground(Theme.surface)
    }
}
