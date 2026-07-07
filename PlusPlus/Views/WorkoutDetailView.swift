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
    @State private var railGesture: RailGestureState = .idle
    @State private var openSwipeRow: PersistentIdentifier?

    /// The two #78 long-press interactions. Rows are identified by
    /// (group, index) — the model never mutates while a gesture is live,
    /// so indices are stable until commit.
    private enum RailGestureState: Equatable {
        case idle
        case dragging(group: Int, index: Int, fingerY: Double, grabOffset: Double)
        case ring(group: Int, edge: RingEdge?, pressY: Double, fingerY: Double)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            railList
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

            HStack(alignment: .center) {
                Text(workout.name)
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(1)
                Spacer()
                HeaderIconButton(systemImage: "slider.horizontal.3", identifier: "workoutSettingsButton") {
                    showingWorkoutSettings = true
                }
            }
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

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "dumbbell")
                .font(.system(size: 32))
                .foregroundStyle(Theme.borderStrong)
            Text("No exercises yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    // MARK: - Rail list (custom gesture surface, #78)
    // ScrollView + absolutely-positioned rows instead of List: we own the
    // whole gesture stack (long-press drag to rearrange, ring-drag for
    // membership, custom swipe reveal). Geometry and drop/ring semantics
    // are pure PlusPlusKit logic (RailArrangement); this layer renders
    // rows at the positions the logic dictates and commits results
    // through the Workout mutations.

    private var groupSizes: [Int] {
        workout.sortedGroups.map { $0.sortedExercises.count }
    }

    private var railList: some View {
        let sizes = groupSizes
        let layout = RailLayout.build(groupSizes: sizes)
        let offsets = rowOffsets(layout: layout, sizes: sizes)
        let groups = workout.sortedGroups
        let ringGroup = activeRingGroup

        // Rows are REAL layout (a plain VStack) so the ScrollView sizes
        // and scrolls naturally — #87's below-the-fold bug came from
        // offset-positioned rows that occupied no layout space. Offsets
        // now carry only the drag-preview deltas.
        return ScrollView {
            VStack(spacing: 0) {
                if groups.isEmpty {
                    emptyHint
                }
                ForEach(Array(groups.enumerated()), id: \.element.persistentModelID) { g, group in
                    ForEach(Array(group.sortedExercises.enumerated()), id: \.element.persistentModelID) { i, workoutExercise in
                        railRow(workoutExercise, group: group, groupIndex: g, index: i, hideLoop: ringGroup == g)
                            .offset(y: offsets[.exercise(group: g, index: i)] ?? 0)
                    }
                }
                addExerciseRow
            }
            .coordinateSpace(name: Self.railSpace)
            .overlay(alignment: .topLeading) { ringHighlight(layout: layout, sizes: sizes) }
            .overlay(alignment: .topLeading) { floatingDragPreview(layout: layout, groups: groups) }
            .animation(.easeOut(duration: 0.16), value: offsets)
            .padding(.top, 10)
            .padding(.leading, 20)
            .padding(.trailing, 14)
            .padding(.bottom, 8)
        }
        .scrollDisabled(railGesture != .idle)
        .sensoryFeedback(.impact(weight: .light), trigger: gestureFeedbackToken)
        .onDisappear { railGesture = .idle }
    }

    private var activeRingGroup: Int? {
        if case .ring(let g, _, _, _) = railGesture { return g }
        return nil
    }

    /// The + row terminating the rail (#84): full-width tap target at the
    /// bottom of the list, where the thumb already is.
    private var addExerciseRow: some View {
        Button {
            pickerDestination = .newGroup
        } label: {
            HStack(spacing: 13) {
                Canvas { context, _ in
                    var spine = Path()
                    spine.move(to: CGPoint(x: 11, y: 0))
                    spine.addLine(to: CGPoint(x: 11, y: 13))
                    context.stroke(spine, with: .color(Theme.border), style: StrokeStyle(lineWidth: 2))
                    let dotRect = CGRect(x: 11 - 8, y: 24 - 8, width: 16, height: 16)
                    context.stroke(
                        Path(ellipseIn: dotRect),
                        with: .color(Theme.borderStrong),
                        style: StrokeStyle(lineWidth: 2, dash: [2.5, 3])
                    )
                    context.draw(
                        Text("+").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.accent),
                        at: CGPoint(x: 11, y: 23.5)
                    )
                }
                .frame(width: 24, height: 48)

                Text("Add exercise")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("addExerciseButton")
    }

    private static let railSpace = "railSpace"

    /// One row: swipe-revealable content with the two long-press zones —
    /// the rail column grabs the ring, the body drags the row.
    private func railRow(_ workoutExercise: WorkoutExercise, group: ExerciseGroup, groupIndex g: Int, index i: Int, hideLoop: Bool) -> some View {
        let height = RailMetrics.v2.rowHeight
        let isDragged: Bool = {
            if case .dragging(let dg, let di, _, _) = railGesture { return dg == g && di == i }
            return false
        }()

        return SwipeRevealRow(
            id: workoutExercise.persistentModelID,
            openRow: $openSwipeRow,
            enabled: railGesture == .idle,
            actionsWidth: 174
        ) {
            ExerciseRailRow(
                workoutExercise: workoutExercise,
                role: railRole(index: i, of: group),
                hideLoop: hideLoop
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if openSwipeRow != nil { openSwipeRow = nil } else { selectedExercise = workoutExercise }
            }
            .overlay(alignment: .leading) {
                // The dot zone: ring gesture lives on the rail column.
                Color.clear
                    .frame(width: 37)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedExercise = workoutExercise }
                    // simultaneousGesture, not gesture: a sequenced
                    // long-press claims touches while it waits, which
                    // blocks the ScrollView from scrolling at all when
                    // the drag starts on a row (every drag does). The
                    // 0.35 s stationary hold still gates activation —
                    // scrolling movement cancels the long press.
                    .simultaneousGesture(ringGesture(groupIndex: g, index: i))
            }
            .simultaneousGesture(dragGesture(groupIndex: g, index: i, rowHeight: height))
        } actions: {
            HStack(spacing: 0) {
                swipeAction("Super", color: Theme.supersetLine) {
                    openSwipeRow = nil
                    pickerDestination = .group(group)
                }
                swipeAction("Dupe", color: Theme.borderStrong) {
                    openSwipeRow = nil
                    duplicateExercise(workoutExercise, in: group)
                }
                swipeAction("Delete", color: Theme.destructive) {
                    openSwipeRow = nil
                    deleteExercise(workoutExercise, in: group)
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isDragged ? 0 : 1)
    }

    private func swipeAction(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 58)
                .frame(maxHeight: .infinity)
                .background(Theme.surface)
                .overlay(Rectangle().frame(width: 1).foregroundStyle(Theme.border), alignment: .leading)
        }
    }

    private func railRole(index: Int, of group: ExerciseGroup) -> RailRole {
        guard group.isSuperset else { return .solo }
        if index == 0 { return .supersetFirst }
        if index == group.sortedExercises.count - 1 { return .supersetLast }
        return .supersetMiddle
    }

    // MARK: Gesture plumbing

    private func dragGesture(groupIndex g: Int, index i: Int, rowHeight: Double) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.railSpace)))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                let layout = RailLayout.build(groupSizes: groupSizes)
                let rowY = layout.row(for: .exercise(group: g, index: i))?.y ?? 0
                if let drag {
                    let grabOffset: Double
                    if case .dragging(_, _, _, let existing) = railGesture {
                        grabOffset = existing
                    } else {
                        grabOffset = drag.startLocation.y - rowY
                    }
                    railGesture = .dragging(group: g, index: i, fingerY: drag.location.y, grabOffset: grabOffset)
                } else if railGesture == .idle {
                    // Long press satisfied, finger not yet moved.
                    railGesture = .dragging(group: g, index: i, fingerY: rowY + rowHeight / 2, grabOffset: rowHeight / 2)
                }
            }
            .onEnded { _ in
                if case .dragging(let dg, let di, let fingerY, let grabOffset) = railGesture {
                    commitDrag(group: dg, index: di, fingerY: fingerY, grabOffset: grabOffset)
                }
                railGesture = .idle
            }
    }

    private func ringGesture(groupIndex g: Int, index i: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.railSpace)))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                let sizes = groupSizes
                let layout = RailLayout.build(groupSizes: sizes)
                let rowMid = layout.row(for: .exercise(group: g, index: i))?.midY ?? 0
                let y = drag.map { Double($0.location.y) } ?? rowMid

                if case .ring(let held, let heldEdge, let pressY, _) = railGesture, held == g {
                    var edge = heldEdge
                    if edge == nil, abs(y - pressY) > 10 {
                        edge = y < pressY ? .top : .bottom
                    }
                    railGesture = .ring(group: g, edge: edge, pressY: pressY, fingerY: y)
                } else {
                    // Superset rows grab their nearest edge immediately; a
                    // solo waits for the first movement so dragging UP can
                    // extend the ring upward too (#87).
                    let edge: RingEdge? = sizes[g] > 1
                        ? RailRing.grabbedEdge(groupSizes: sizes, group: g, pressedIndex: i)
                        : nil
                    railGesture = .ring(group: g, edge: edge, pressY: y, fingerY: y)
                }
            }
            .onEnded { _ in
                if case .ring(let rg, let edge?, _, let fingerY) = railGesture {
                    commitRing(group: rg, edge: edge, fingerY: fingerY)
                }
                railGesture = .idle
            }
    }

    /// The dragged row's tentative drop target, from the floating row's
    /// visual center.
    private func tentativeTarget(sizes: [Int]) -> RailDropTarget? {
        guard case .dragging(let g, let i, let fingerY, let grabOffset) = railGesture else { return nil }
        let centerY = fingerY - grabOffset + RailMetrics.v2.rowHeight / 2
        return RailDrag.nearestTarget(groupSizes: sizes, dragging: (group: g, index: i), fingerY: centerY)
    }

    /// Per-row deltas from the natural layout. Empty when idle; during a
    /// drag every surviving row shifts by (previewY − idleY) and the
    /// dragged row gets no entry — it stays anchored (hidden) in place,
    /// so nothing ever flies to the top of the viewport (#87).
    private func rowOffsets(layout: RailLayout, sizes: [Int]) -> [RailRowKind: Double] {
        guard case .dragging(let g, let i, _, _) = railGesture,
              let target = tentativeTarget(sizes: sizes) else { return [:] }
        let preview = RailDrag.previewPositions(groupSizes: sizes, dragging: (group: g, index: i), target: target)
        var offsets: [RailRowKind: Double] = [:]
        for row in layout.rows {
            if let previewY = preview[row.kind] {
                offsets[row.kind] = previewY - row.y
            }
        }
        return offsets
    }

    /// Changes whenever the tentative outcome changes — drives one haptic
    /// tick per slot/row crossed.
    private var gestureFeedbackToken: Int {
        let sizes = groupSizes
        switch railGesture {
        case .idle:
            return 0
        case .dragging:
            return tentativeTarget(sizes: sizes)?.hashValue ?? 0
        case .ring(let g, let edge, _, let fingerY):
            guard let edge else { return 1 }
            let span = RailRing.span(groupSizes: sizes, group: g, edge: edge, fingerY: fingerY)
            return span.firstFlat &* 31 &+ span.lastFlat
        }
    }

    @ViewBuilder
    private func ringHighlight(layout: RailLayout, sizes: [Int]) -> some View {
        if case .ring(let g, let edge, _, let fingerY) = railGesture, sizes.indices.contains(g) {
            // Before a direction is chosen (solo press, finger still) the
            // highlight spans the pressed group; after, the live span.
            let span: RingSpan? = edge.map { RailRing.span(groupSizes: sizes, group: g, edge: $0, fingerY: fingerY) }
            let firstFlat = span?.firstFlat ?? RailLayout.flatIndex(groupSizes: sizes, group: g, index: 0)
            let lastFlat = span?.lastFlat ?? (firstFlat + sizes[g] - 1)
            if let first = exerciseRow(layout: layout, sizes: sizes, flat: firstFlat),
               let last = exerciseRow(layout: layout, sizes: sizes, flat: lastFlat) {
                // Full-width ring: the tentative membership reads across
                // the whole rows, not under the thumb. Breathing room on
                // all sides; the list's 10 pt top inset keeps the stroke
                // visible even when the span starts at the first row.
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.supersetLine.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Theme.supersetLine, lineWidth: 2)
                    )
                    .frame(height: last.maxY - first.y + 12)
                    .padding(.horizontal, -8)
                    .offset(y: first.y - 6)
                    .allowsHitTesting(false)
            }
        }
    }

    private func exerciseRow(layout: RailLayout, sizes: [Int], flat: Int) -> RailRow? {
        var remaining = flat
        for (g, size) in sizes.enumerated() {
            if remaining < size {
                return layout.row(for: .exercise(group: g, index: remaining))
            }
            remaining -= size
        }
        return nil
    }

    @ViewBuilder
    private func floatingDragPreview(layout: RailLayout, groups: [ExerciseGroup]) -> some View {
        if case .dragging(let g, let i, let fingerY, let grabOffset) = railGesture,
           groups.indices.contains(g), groups[g].sortedExercises.indices.contains(i) {
            let workoutExercise = groups[g].sortedExercises[i]
            ExerciseRailRow(workoutExercise: workoutExercise, role: .solo)
                .padding(.horizontal, 8)
                .frame(height: RailMetrics.v2.rowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderStrong))
                .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                .scaleEffect(1.02)
                .offset(y: fingerY - grabOffset)
                .zIndex(10)
                .allowsHitTesting(false)
        }
    }

    // MARK: Gesture commits

    private func commitDrag(group g: Int, index i: Int, fingerY: Double, grabOffset: Double) {
        let sizes = groupSizes
        guard sizes.indices.contains(g), i < sizes[g] else { return }
        let centerY = fingerY - grabOffset + RailMetrics.v2.rowHeight / 2
        guard let target = RailDrag.nearestTarget(groupSizes: sizes, dragging: (group: g, index: i), fingerY: centerY) else { return }

        let groups = workout.sortedGroups
        guard groups.indices.contains(g), groups[g].sortedExercises.indices.contains(i) else { return }
        let workoutExercise = groups[g].sortedExercises[i]

        switch target {
        case .gap(let gap):
            workout.placeSolo(workoutExercise, atGap: gap, context: modelContext)
        case .within(_, let index):
            workout.reorderExercise(workoutExercise, toIndex: index)
        }
    }

    private func commitRing(group g: Int, edge: RingEdge, fingerY: Double) {
        let sizes = groupSizes
        guard sizes.indices.contains(g) else { return }
        let span = RailRing.span(groupSizes: sizes, group: g, edge: edge, fingerY: fingerY)
        guard !span.isNoOp else { return }
        let group = workout.sortedGroups[g]

        for _ in 0..<span.absorbAfter {
            let groups = workout.sortedGroups
            guard let index = groups.firstIndex(where: { $0 === group }),
                  groups.indices.contains(index + 1) else { break }
            workout.mergeSoloGroup(groups[index + 1], direction: -1, context: modelContext)
        }
        for _ in 0..<span.absorbBefore {
            let groups = workout.sortedGroups
            guard let index = groups.firstIndex(where: { $0 === group }),
                  index > 0 else { break }
            workout.mergeSoloGroup(groups[index - 1], direction: 1, context: modelContext)
        }
        for _ in 0..<span.ejectLast {
            guard group.isSuperset, let last = group.sortedExercises.last else { break }
            workout.splitExercise(last, context: modelContext)
        }
        for _ in 0..<span.ejectFirst {
            guard group.isSuperset, let first = group.sortedExercises.first else { break }
            workout.splitExercise(first, placeAbove: true, context: modelContext)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
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
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.bar)
        }
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

// MARK: - Swipe reveal

/// Minimal trailing-actions swipe, since List's swipeActions left with
/// List (#78). Horizontal-dominant drags reveal the actions; vertical
/// movement is left to the ScrollView. One row open at a time via the
/// shared `openRow` binding.
private struct SwipeRevealRow<Content: View, Actions: View>: View {
    let id: PersistentIdentifier
    @Binding var openRow: PersistentIdentifier?
    let enabled: Bool
    let actionsWidth: CGFloat
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    @State private var dragX: CGFloat = 0

    private var restingOffset: CGFloat {
        openRow == id ? -actionsWidth : 0
    }

    private var offset: CGFloat {
        min(0, max(restingOffset + dragX, -actionsWidth - 24))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            actions()
                .frame(width: actionsWidth)
                .frame(maxHeight: .infinity)
                .opacity(offset < -12 ? 1 : 0)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.background)
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 16)
                        .onChanged { value in
                            guard enabled,
                                  abs(value.translation.width) > abs(value.translation.height)
                            else { return }
                            dragX = value.translation.width
                        }
                        .onEnded { value in
                            guard enabled else { return }
                            if dragX != 0 {
                                let projected = restingOffset + value.predictedEndTranslation.width
                                openRow = projected < -actionsWidth / 2 ? id : (openRow == id ? nil : openRow)
                            }
                            dragX = 0
                        }
                )
        }
        .clipped()
        .animation(.easeOut(duration: 0.18), value: offset)
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
    /// Ring-edit mode (#87): the small loop and the expanded full-width
    /// ring are mutually exclusive — the active group's rows drop their
    /// loop drawing while the highlight is up.
    var hideLoop = false

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
            RailGlyph(role: hideLoop ? .solo : role, height: 48, dotY: 24)
                .frame(width: 24, height: 48)

            Text(workoutExercise.exercise?.name ?? "Unknown")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 6)

            if isDuration {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
            }
            Text(summary)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(height: 48)
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
                arrow(x: 3, tipY: dotY + 8, pointingDown: false)
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
