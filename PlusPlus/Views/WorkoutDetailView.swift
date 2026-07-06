import SwiftUI
import SwiftData
import PlusPlusKit

/// Workout detail, v2 (#61): a compact program view — meta line with
/// estimated time and rest, exercise rows on a rail with supersets drawn
/// as a stadium loop, swipe actions, and a pinned Start/Add bar. Editing
/// a row happens in ExerciseDetailSheet (#62).
struct WorkoutDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var workout: Workout

    @State private var filterState = ExerciseFilterState()
    @State private var pickerDestination: PickerDestination?
    @State private var activeSession: WorkoutSession?
    @State private var showingWorkoutSettings = false
    @State private var selectedExercise: WorkoutExercise?

    var body: some View {
        VStack(spacing: 0) {
            header

            if workout.groups.isEmpty {
                emptyState
            } else {
                railList
            }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(item: $pickerDestination) { destination in
            ExercisePickerView(filterState: filterState) { exercise in
                addExercise(exercise, to: destination)
            }
        }
        .sheet(isPresented: $showingWorkoutSettings) {
            WorkoutSettingsSheet(workout: workout)
                .presentationDetents([.height(320)])
        }
        .sheet(item: $selectedExercise) { workoutExercise in
            ExerciseDetailSheet(
                workout: workout,
                workoutExercise: workoutExercise,
                onAddToSuperset: { group in pickerDestination = .group(group) }
            )
            .presentationDetents([.large])
        }
        .fullScreenCover(item: $activeSession) { session in
            ActiveSessionView(session: session)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                    Text("Workouts")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 6)
            }
            .accessibilityIdentifier("backButton")

            Text(workout.name)
                .font(.system(size: 26, weight: .bold))
                .lineLimit(1)
                .padding(.top, 2)

            if !workout.groups.isEmpty {
                HStack(spacing: 14) {
                    (Text(estimatedTimeText).font(.system(size: 12.5, design: .monospaced)).bold().foregroundStyle(Theme.textPrimary)
                        + Text(" est").font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary))
                    Button {
                        showingWorkoutSettings = true
                    } label: {
                        (Text("rest ").font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                            + Text(restText).font(.system(size: 12.5, design: .monospaced)).bold().foregroundStyle(Theme.textPrimary)
                            + Text(" ▾").font(.system(size: 10)).foregroundStyle(Theme.textSecondary))
                    }
                    .accessibilityIdentifier("workoutSettingsButton")
                }
                .padding(.top, 6)

                Button {
                    showingWorkoutSettings = true
                } label: {
                    Text(workout.notes ?? "add notes…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(workout.notes == nil ? Theme.textFaint : Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.top, 7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var estimatedTimeText: String {
        let minutes = max(5, Int((Double(workout.estimatedSeconds) / 300).rounded()) * 5)
        return "~\(minutes) min"
    }

    private var restText: String {
        WorkoutMetric.duration.formatted(Double(workout.restSeconds))
            + (workout.restSeconds < 60 ? "s" : "")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "dumbbell")
                .font(.system(size: 40))
                .foregroundStyle(Theme.borderStrong)
            Text("No exercises")
                .font(.system(size: 18, weight: .bold))
            Text("Tap below to add exercises to this workout.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rail list

    private var railList: some View {
        List {
            ForEach(workout.sortedGroups) { group in
                if group.isSuperset {
                    SupersetCaptionRow(
                        group: group,
                        groupCount: workout.sortedGroups.count,
                        onAddToSuperset: { pickerDestination = .group(group) },
                        onMoveUp: { moveGroup(group, by: -1) },
                        onMoveDown: { moveGroup(group, by: 1) },
                        onDelete: { deleteGroup(group) }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 14))
                }

                ForEach(Array(group.sortedExercises.enumerated()), id: \.element.persistentModelID) { index, workoutExercise in
                    ExerciseRailRow(
                        workoutExercise: workoutExercise,
                        role: railRole(index: index, of: group),
                        topPadding: group.isSuperset || index > 0 ? 0 : 6
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 14))
                    .contentShape(Rectangle())
                    .onTapGesture { selectedExercise = workoutExercise }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteExercise(workoutExercise, in: group)
                        } label: {
                            Label("Delete", systemImage: "xmark")
                        }
                        Button {
                            duplicateExercise(workoutExercise, in: group)
                        } label: {
                            Label("Dupe", systemImage: "plus.circle")
                        }
                        .tint(Theme.borderStrong)
                        Button {
                            pickerDestination = .group(group)
                        } label: {
                            Label("Super", systemImage: "square.on.square")
                        }
                        .tint(Theme.supersetLine)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 10)
    }

    private func railRole(index: Int, of group: ExerciseGroup) -> RailRole {
        guard group.isSuperset else { return .solo }
        if index == 0 { return .supersetFirst }
        if index == group.sortedExercises.count - 1 { return .supersetLast }
        return .supersetMiddle
    }

    private var bottomBar: some View {
        VStack(spacing: 9) {
            if !workout.groups.isEmpty {
                Button {
                    activeSession = WorkoutSession.start(from: workout, context: modelContext)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "play.fill").font(.system(size: 13))
                        Text("Start workout").font(.system(size: 15.5, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Theme.accentButton, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                }
                .accessibilityIdentifier("startWorkoutButton")
            }

            Button {
                pickerDestination = .newGroup
            } label: {
                HStack(spacing: 8) {
                    Text("+").font(.system(size: 16, design: .monospaced)).foregroundStyle(Theme.accent)
                    Text("Add exercise").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.borderStrong))
            }
            .accessibilityIdentifier("addExerciseButton")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Mutations

    private func addExercise(_ exercise: Exercise, to destination: PickerDestination) {
        switch destination {
        case .newGroup:
            workout.addExerciseInNewGroup(exercise, context: modelContext)
        case .group(let group):
            workout.addExercise(exercise, to: group, context: modelContext)
        }
    }

    private func deleteExercise(_ workoutExercise: WorkoutExercise, in group: ExerciseGroup) {
        modelContext.delete(workoutExercise)
        group.reindexExercises()
        if group.sortedExercises.isEmpty {
            modelContext.delete(group)
            workout.reindexGroups()
        }
    }

    /// The design's DUPE: copy the exercise (with its targets) into a new
    /// solo group directly below this one.
    private func duplicateExercise(_ workoutExercise: WorkoutExercise, in group: ExerciseGroup) {
        guard let exercise = workoutExercise.exercise else { return }

        for later in workout.sortedGroups where later.order > group.order {
            later.order += 1
        }
        let copyGroup = ExerciseGroup(order: group.order + 1, sets: group.sets)
        copyGroup.workout = workout
        modelContext.insert(copyGroup)

        let copy = WorkoutExercise(exercise: exercise, order: 0)
        copy.weight = workoutExercise.weight
        copy.reps = workoutExercise.reps
        copy.repsUpper = workoutExercise.repsUpper
        copy.durationSeconds = workoutExercise.durationSeconds
        copy.group = copyGroup
        modelContext.insert(copy)
        workout.reindexGroups()
    }

    private func deleteGroup(_ group: ExerciseGroup) {
        modelContext.delete(group)
        workout.reindexGroups()
    }

    private func moveGroup(_ group: ExerciseGroup, by delta: Int) {
        var sorted = workout.sortedGroups
        guard let index = sorted.firstIndex(where: { $0 === group }) else { return }
        let target = index + delta
        guard sorted.indices.contains(target) else { return }
        sorted.swapAt(index, target)
        for (newOrder, moved) in sorted.enumerated() {
            moved.order = newOrder
        }
    }
}

/// Where a picked exercise should land: a fresh group at the end, or an
/// existing group (forming a superset).
enum PickerDestination: Identifiable {
    case newGroup
    case group(ExerciseGroup)

    var id: AnyHashable {
        switch self {
        case .newGroup: AnyHashable("newGroup")
        case .group(let group): AnyHashable(group.persistentModelID)
        }
    }
}

// MARK: - Superset caption

private struct SupersetCaptionRow: View {
    let group: ExerciseGroup
    let groupCount: Int
    let onAddToSuperset: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            (Text("⧉ ").font(.system(size: 10.5)) + Text("SUPERSET"))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.superset)
                .kerning(0.7)
                .padding(.leading, 9)
            Spacer()
            Menu {
                Button("Add to superset", systemImage: "plus.square.on.square", action: onAddToSuperset)
                Button("Move up", systemImage: "arrow.up", action: onMoveUp)
                    .disabled(group.order == 0)
                Button("Move down", systemImage: "arrow.down", action: onMoveDown)
                    .disabled(group.order == groupCount - 1)
                Button("Delete group", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 26, height: 22)
            }
            .accessibilityIdentifier("groupMenu")
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}

// MARK: - Rail rows

/// How a row sits on the rail: alone, or as part of a superset loop.
enum RailRole {
    case solo
    case supersetFirst
    case supersetMiddle
    case supersetLast
}

private struct ExerciseRailRow: View {
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    let workoutExercise: WorkoutExercise
    let role: RailRole
    let topPadding: CGFloat

    private var isDuration: Bool {
        workoutExercise.exercise?.exerciseType == .duration
    }

    /// "3×15", "3×10 · 5lb", "2×45s" — the condensed target summary.
    private var summary: String {
        let sets = workoutExercise.group?.sets ?? 1
        let unit = WeightUnit(rawValue: weightUnitRaw) ?? .lb
        if isDuration {
            let dur = workoutExercise.durationSeconds.map { seconds in
                seconds >= 60
                    ? WorkoutMetric.duration.formatted(Double(seconds))
                    : "\(seconds)s"
            } ?? "—"
            return "\(sets)×\(dur)"
        }
        let reps = RepTarget(lower: workoutExercise.reps, upper: workoutExercise.repsUpper).display
        var text = "\(sets)×\(reps)"
        if let weight = workoutExercise.weight {
            text += " · \(WorkoutMetric.weight.formatted(weight))\(unit.symbol)"
        }
        return text
    }

    var body: some View {
        HStack(spacing: 13) {
            RailGlyph(role: role, height: 48 + topPadding, dotY: 24 + topPadding)
                .frame(width: 24, height: 48 + topPadding)

            Text(workoutExercise.exercise?.name ?? "Unknown")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .padding(.top, topPadding)

            Spacer(minLength: 6)

            if isDuration {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.top, topPadding)
            }
            Text(summary)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, topPadding)
        }
        .frame(height: 48 + topPadding)
    }
}

/// The rail drawing beside each exercise row: a spine for solo rows, and
/// a stadium loop (blue) with flow arrows around superset members. The
/// geometry mirrors the prototype: dot center x=11, loop sides x=3/x=19,
/// cap radius 8, 2 pt strokes.
struct RailGlyph: View {
    let role: RailRole
    let height: CGFloat
    let dotY: CGFloat

    var body: some View {
        Canvas { context, _ in
            let spine = Theme.border
            let loop = Theme.supersetLine
            let solid = StrokeStyle(lineWidth: 2)
            let dashed = StrokeStyle(lineWidth: 2, dash: [3.5, 4.5])
            let loopStyle = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

            func vline(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat, style: StrokeStyle, color: Color) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: y0))
                path.addLine(to: CGPoint(x: x, y: y1))
                context.stroke(path, with: .color(color), style: style)
            }

            /// Half-stadium cap through the dot row: (3,dotY) → (19,dotY),
            /// bulging up (top cap) or down (bottom cap).
            func cap(up: Bool) {
                var path = Path()
                let bulge: CGFloat = up ? dotY - 10.7 : dotY + 10.7
                path.move(to: CGPoint(x: 3, y: dotY))
                path.addCurve(
                    to: CGPoint(x: 19, y: dotY),
                    control1: CGPoint(x: 3, y: bulge),
                    control2: CGPoint(x: 19, y: bulge)
                )
                context.stroke(path, with: .color(loop), style: loopStyle)
            }

            func arrow(x: CGFloat, tipY: CGFloat, pointingDown: Bool) {
                var path = Path()
                let backY = pointingDown ? tipY - 4 : tipY + 4
                path.move(to: CGPoint(x: x - 2.5, y: backY))
                path.addLine(to: CGPoint(x: x, y: tipY))
                path.addLine(to: CGPoint(x: x + 2.5, y: backY))
                context.stroke(path, with: .color(loop), style: loopStyle)
            }

            switch role {
            case .solo:
                vline(11, 0, height, style: solid, color: spine)
            case .supersetFirst:
                vline(11, 0, dotY - 8, style: solid, color: spine)
                vline(11, dotY, height, style: dashed, color: spine)
                cap(up: true)
                vline(3, dotY, height, style: loopStyle, color: loop)
                vline(19, dotY, height, style: loopStyle, color: loop)
                arrow(x: 3, tipY: dotY + 12, pointingDown: true)
            case .supersetMiddle:
                vline(11, 0, height, style: dashed, color: spine)
                vline(3, 0, height, style: loopStyle, color: loop)
                vline(19, 0, height, style: loopStyle, color: loop)
            case .supersetLast:
                vline(11, 0, dotY, style: dashed, color: spine)
                vline(11, dotY + 8, height, style: solid, color: spine)
                cap(up: false)
                vline(3, 0, dotY, style: loopStyle, color: loop)
                vline(19, 0, dotY - 10, style: loopStyle, color: loop)
                vline(19, dotY - 6.5, dotY, style: loopStyle, color: loop)
                arrow(x: 19, tipY: dotY - 10, pointingDown: true)
            }

            // The member dot, drawn last so it sits on the lines.
            let dotRect = CGRect(x: 11 - 5, y: dotY - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: dotRect), with: .color(Theme.background))
            context.stroke(
                Path(ellipseIn: dotRect.insetBy(dx: 1, dy: 1)),
                with: .color(Theme.borderStrong),
                style: StrokeStyle(lineWidth: 2)
            )
        }
    }
}

// MARK: - Workout settings sheet (rest + notes)

struct WorkoutSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Text("Workout settings").font(.system(size: 15, weight: .bold))
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button("Done") { dismiss() }
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.top, 14)

            SheetSectionLabel("BETWEEN SETS")
                .padding(.top, 16)

            MetricStepperRow(
                label: "Rest",
                value: WorkoutMetric.rest.displayText(Double(workout.restSeconds)),
                identifier: "rest",
                onDecrement: { workout.restSeconds = Int(WorkoutMetric.rest.decremented(Double(workout.restSeconds))) },
                onIncrement: { workout.restSeconds = Int(WorkoutMetric.rest.incremented(Double(workout.restSeconds))) }
            )
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))

            SheetSectionLabel("NOTES")
                .padding(.top, 16)

            TextField("Intent for this workout — shown when you start it", text: notesBinding, axis: .vertical)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                .accessibilityIdentifier("workoutNotesField")

            Text("Shown once, when you start the workout.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 6)

            Spacer()
        }
        .padding(.horizontal, 18)
        .presentationBackground(Theme.surface)
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { workout.notes ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                workout.notes = trimmed.isEmpty ? nil : newValue
            }
        )
    }
}

/// Mono section caption used inside v2 sheets.
struct SheetSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.textSecondary)
            .kerning(0.7)
            .padding(.bottom, 6)
    }
}
