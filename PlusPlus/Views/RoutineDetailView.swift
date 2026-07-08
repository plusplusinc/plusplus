import SwiftUI
import SwiftData
import TipKit
import PlusPlusKit

/// Routine detail, v2 (#61): a compact program view — meta line with
/// estimated time and rest, exercise rows on a rail with supersets drawn
/// as a stadium loop, swipe actions, and a pinned Start/Add bar. Editing
/// a row happens in ExerciseDetailSheet (#62).
struct RoutineDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var routine: Routine

    @State private var filterState = ExerciseFilterState()
    @State private var pickerDestination: PickerDestination?
    @State private var activeSession: WorkoutSession?
    @State private var showingRoutineSettings = false
    @State private var showingShareSheet = false
    @State private var selectedExercise: RoutineExercise?
    @State private var railGesture: RailGestureState = .idle
    @State private var openSwipeRow: PersistentIdentifier?
    /// Rows track Dynamic Type: 52 pt at standard body size, growing with
    /// the user's setting so 17 pt+ text never clips (#82).
    @ScaledMetric(relativeTo: .body) private var railRowHeight: Double = 52

    private var railMetrics: RailMetrics { RailMetrics(rowHeight: railRowHeight) }

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
        .pushedScreenChrome(onBack: { dismiss() })
        .toolbar {
            // Trailing actions as glass circles (#198), same treatment
            // as the back chevron. Share keeps its UIKit sheet (#178).
            if !routine.groups.isEmpty, shareURL != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("shareRoutineButton")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingRoutineSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityIdentifier("routineSettingsButton")
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareURL {
                ActivitySheet(items: [
                    url,
                    ShareMessageItem(text: "My \(routine.name) routine on PlusPlus", subject: routine.name),
                ])
                .presentationDetents([.medium, .large])
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(item: $pickerDestination) { destination in
            ExercisePickerView(filterState: filterState) { exercise in
                addExercise(exercise, to: destination)
            }
        }
        .navigationDestination(isPresented: $showingRoutineSettings) {
            RoutineSettingsScreen(routine: routine) {
                // Delete pops both settings and detail before the model
                // dies — a rendered @Bindable to a deleted routine is a
                // crash waiting on the next body pass.
                showingRoutineSettings = false
                dismiss()
                Task { @MainActor in
                    modelContext.delete(routine)
                }
            }
        }
        .sheet(item: $selectedExercise) { routineExercise in
            ExerciseDetailSheet(
                routine: routine,
                routineExercise: routineExercise,
                onAddToSuperset: { group in pickerDestination = .group(group) }
            )
            .presentationDetents([.large])
        }
        .fullScreenCover(item: $activeSession) { session in
            ActiveSessionView(session: session)
        }
    }

    /// The share link for this routine — built fresh on each render so
    /// edits are always reflected. Sorted-keys JSON keeps it stable.
    private var shareURL: URL? {
        let dto = InterchangeMapping.makeDTO(routine)
        let exercises = routine.sortedGroups
            .flatMap(\.sortedExercises)
            .compactMap(\.exercise)
        var seen = Set<String>()
        let exerciseDTOs = exercises
            .filter { seen.insert($0.name.lowercased()).inserted }
            .map { InterchangeMapping.makeDTO($0) }
        let unit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: WeightUnitSetting.key) ?? "") ?? .lb
        let payload = RoutineShareLink.Payload(routine: dto, exercises: exerciseDTOs, units: unit)
        return try? RoutineShareLink.url(for: payload)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back + share + settings live in the system toolbar (#198,
            // glass circles); the header keeps name and facts only.
            Text(routine.name)
                .font(.system(.title, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

            if !routine.groups.isEmpty {
                // Facts, not inputs (v4 §A): schedule value first (ink,
                // semibold), then rest + estimate as secondary meta.
                // Nothing here is tappable — the settings button is the
                // single edit entry.
                (scheduleFactText
                    + Text("  ·  rest \(restText)  ·  \(estimatedTimeText)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary))
                    .padding(.top, 8)

                if let notes = routine.notes {
                    Text(notes)
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var estimatedTimeText: String {
        let minutes = max(5, Int((Double(routine.estimatedSeconds) / 300).rounded()) * 5)
        return "~\(minutes) min"
    }

    private var restText: String {
        WorkoutMetric.duration.formatted(Double(routine.restSeconds))
            + (routine.restSeconds < 60 ? "s" : "")
    }

    /// Schedule value in ink semibold; "unscheduled" recedes to faint.
    private var scheduleFactText: Text {
        let unscheduled = routine.schedule.normalized == .unscheduled
        return Text(unscheduled ? "unscheduled" : routine.schedule.shortLabel)
            .font(.system(.footnote, design: .monospaced, weight: unscheduled ? .regular : .semibold))
            .foregroundStyle(unscheduled ? Theme.textFaint : Theme.textPrimary)
    }

    // The "No exercises yet" empty hint died (#209): the rail's
    // Add-exercise button IS the empty state.

    // MARK: - Rail list (custom gesture surface, #78)
    // ScrollView + absolutely-positioned rows instead of List: we own the
    // whole gesture stack (long-press drag to rearrange, ring-drag for
    // membership, custom swipe reveal). Geometry and drop/ring semantics
    // are pure PlusPlusKit logic (RailArrangement); this layer renders
    // rows at the positions the logic dictates and commits results
    // through the Routine mutations.

    private var groupSizes: [Int] {
        routine.sortedGroups.map { $0.sortedExercises.count }
    }

    private var railList: some View {
        let sizes = groupSizes
        let layout = RailLayout.build(groupSizes: sizes, metrics: railMetrics)
        let offsets = rowOffsets(layout: layout, sizes: sizes)
        let groups = routine.sortedGroups
        let ringGroup = activeRingGroup

        // Rows are REAL layout (a plain VStack) so the ScrollView sizes
        // and scrolls naturally — #87's below-the-fold bug came from
        // offset-positioned rows that occupied no layout space. Offsets
        // now carry only the drag-preview deltas.
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.persistentModelID) { g, group in
                    ForEach(Array(group.sortedExercises.enumerated()), id: \.element.persistentModelID) { i, routineExercise in
                        railRow(routineExercise, group: group, groupIndex: g, index: i, hideLoop: ringGroup == g)
                            .offset(y: offsets[.exercise(group: g, index: i)] ?? 0)
                    }
                }
                addExerciseRow
            }
            .overlay(alignment: .topLeading) {
                // The long-press layer for both #78 gestures. UIKit, not
                // SwiftUI — see RailGestureRecognizer for the why.
                RailGestureRecognizer(
                    shouldReceive: { exerciseRowExists(at: $0.y) },
                    began: { beginRailGesture(at: $0) },
                    moved: { moveRailGesture(to: $0) },
                    ended: { location, cancelled in endRailGesture(at: location, cancelled: cancelled) }
                )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
            }
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
                Canvas { context, size in
                    let mid = size.height / 2
                    var spine = Path()
                    spine.move(to: CGPoint(x: 15, y: 0))
                    spine.addLine(to: CGPoint(x: 15, y: mid - 11))
                    context.stroke(spine, with: .color(Theme.border), style: StrokeStyle(lineWidth: 2))
                    let dotRect = CGRect(x: 15 - 8, y: mid - 8, width: 16, height: 16)
                    context.stroke(
                        Path(ellipseIn: dotRect),
                        with: .color(Theme.borderStrong),
                        style: StrokeStyle(lineWidth: 2, dash: [2.5, 3])
                    )
                    // The + stays green ONLY here — it marks a future
                    // node on the rail (§H).
                    context.draw(
                        Text("+").font(.system(.footnote, design: .monospaced, weight: .semibold)).foregroundStyle(Theme.accent),
                        at: CGPoint(x: 15, y: mid - 0.5)
                    )
                }
                .frame(width: 28, height: railRowHeight)

                // A button, not a passive row (#209): green creation
                // grammar in a dashed capsule, so the empty state has a
                // single obvious action.
                Text("Add exercise")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                Spacer(minLength: 0)
            }
            .frame(height: railRowHeight)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("addExerciseButton")
    }

    /// One row: swipe-revealable content with the two long-press zones —
    /// the rail column grabs the ring, the body drags the row.
    private func railRow(_ routineExercise: RoutineExercise, group: ExerciseGroup, groupIndex g: Int, index i: Int, hideLoop: Bool) -> some View {
        let height = railRowHeight
        let isDragged: Bool = {
            if case .dragging(let dg, let di, _, _) = railGesture { return dg == g && di == i }
            return false
        }()

        return SwipeRevealRow(
            id: routineExercise.persistentModelID,
            openRow: $openSwipeRow,
            enabled: railGesture == .idle,
            actionsWidth: 116
        ) {
            ExerciseRailRow(
                routineExercise: routineExercise,
                role: railRole(index: i, of: group),
                rowHeight: railRowHeight,
                hideLoop: hideLoop
            )
            .contentShape(Rectangle())
            .onTapGesture {
                // A second finger must not open sheets (and mutate the
                // model) while a rail gesture is live.
                guard railGesture == .idle else { return }
                if openSwipeRow != nil { openSwipeRow = nil } else { selectedExercise = routineExercise }
            }
            .overlay(alignment: .leading) {
                // The dot zone still taps through to the sheet; its ring
                // gesture lives in the UIKit long-press layer, routed by
                // the touch's x position.
                Color.clear
                    .frame(width: Self.dotZoneWidth)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard railGesture == .idle else { return }
                        selectedExercise = routineExercise
                    }
            }
        } actions: {
            HStack(spacing: 0) {
                SwipeActionButton(label: "DUPE", color: Theme.textSecondary) {
                    openSwipeRow = nil
                    duplicateExercise(routineExercise, in: group)
                }
                SwipeActionButton(label: "DELETE", color: Theme.destructive) {
                    openSwipeRow = nil
                    deleteExercise(routineExercise, in: group)
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isDragged ? 0 : 1)
    }

    private func railRole(index: Int, of group: ExerciseGroup) -> RailRole {
        guard group.isSuperset else { return .solo }
        if index == 0 { return .supersetFirst }
        if index == group.sortedExercises.count - 1 { return .supersetLast }
        return .supersetMiddle
    }

    // MARK: Gesture plumbing (UIKit long-press layer — RailGestureRecognizer)

    /// Width of the rail column at each row's leading edge: a press that
    /// starts here is the ring gesture; anywhere else on the row drags it.
    private static let dotZoneWidth: Double = 41

    /// True only for a y actually INSIDE an exercise row's extent.
    /// RailLayout.exercise(at:) clamps to the nearest row by design
    /// (ring spans rely on that), so an unbounded call here would make
    /// every press in the viewport — the add row, the empty space below
    /// a short list — grab the nearest row (bug hunt finding 1).
    private func exerciseRowExists(at y: Double) -> Bool {
        let layout = RailLayout.build(groupSizes: groupSizes, metrics: railMetrics)
        guard let last = layout.rows.last, y >= 0, y < last.maxY else { return false }
        return layout.exercise(at: y) != nil
    }

    private func beginRailGesture(at location: CGPoint) {
        let x = Double(location.x)
        let y = Double(location.y)
        guard railGesture == .idle else { return }
        // A press with a swipe open just closes the swipe.
        guard openSwipeRow == nil else {
            openSwipeRow = nil
            return
        }
        let sizes = groupSizes
        let layout = RailLayout.build(groupSizes: sizes, metrics: railMetrics)
        // Same bound as shouldReceive: never grab from outside a row.
        guard let last = layout.rows.last, y >= 0, y < last.maxY,
              let (g, i) = layout.exercise(at: y) else { return }

        if x < Self.dotZoneWidth {
            // Superset rows grab their nearest ring edge immediately; a
            // solo waits for the first movement so dragging UP can extend
            // the ring upward too (#87).
            let edge: RingEdge? = sizes[g] > 1
                ? RailRing.grabbedEdge(groupSizes: sizes, group: g, pressedIndex: i)
                : nil
            railGesture = .ring(group: g, edge: edge, pressY: y, fingerY: y)
        } else {
            let rowY = layout.row(for: .exercise(group: g, index: i))?.y ?? 0
            railGesture = .dragging(group: g, index: i, fingerY: y, grabOffset: y - rowY)
        }
    }

    private func moveRailGesture(to location: CGPoint) {
        let y = Double(location.y)
        switch railGesture {
        case .idle:
            break
        case .dragging(let g, let i, _, let grabOffset):
            railGesture = .dragging(group: g, index: i, fingerY: y, grabOffset: grabOffset)
        case .ring(let g, let heldEdge, let pressY, _):
            var edge = heldEdge
            if edge == nil, abs(y - pressY) > 10 {
                edge = y < pressY ? .top : .bottom
            }
            railGesture = .ring(group: g, edge: edge, pressY: pressY, fingerY: y)
        }
    }

    private func endRailGesture(at location: CGPoint, cancelled: Bool) {
        let y = Double(location.y)
        defer { railGesture = .idle }
        guard !cancelled else { return }
        switch railGesture {
        case .idle:
            break
        case .dragging(let g, let i, _, let grabOffset):
            commitDrag(group: g, index: i, fingerY: y, grabOffset: grabOffset)
        case .ring(let g, let edge, _, _):
            if let edge { commitRing(group: g, edge: edge, fingerY: y) }
        }
    }

    /// The dragged row's tentative drop target, from the floating row's
    /// visual center.
    private func tentativeTarget(sizes: [Int]) -> RailDropTarget? {
        guard case .dragging(let g, let i, let fingerY, let grabOffset) = railGesture else { return nil }
        let centerY = fingerY - grabOffset + railRowHeight / 2
        return RailDrag.nearestTarget(groupSizes: sizes, dragging: (group: g, index: i), fingerY: centerY, metrics: railMetrics)
    }

    /// Per-row deltas from the natural layout. Empty when idle; during a
    /// drag every surviving row shifts by (previewY − idleY) and the
    /// dragged row gets no entry — it stays anchored (hidden) in place,
    /// so nothing ever flies to the top of the viewport (#87).
    private func rowOffsets(layout: RailLayout, sizes: [Int]) -> [RailRowKind: Double] {
        guard case .dragging(let g, let i, _, _) = railGesture,
              let target = tentativeTarget(sizes: sizes) else { return [:] }
        let preview = RailDrag.previewPositions(groupSizes: sizes, dragging: (group: g, index: i), target: target, metrics: railMetrics)
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
            let span = RailRing.span(groupSizes: sizes, group: g, edge: edge, fingerY: fingerY, metrics: railMetrics)
            return span.firstFlat &* 31 &+ span.lastFlat
        }
    }

    @ViewBuilder
    private func ringHighlight(layout: RailLayout, sizes: [Int]) -> some View {
        if case .ring(let g, let edge, _, let fingerY) = railGesture, sizes.indices.contains(g) {
            // Before a direction is chosen (solo press, finger still) the
            // highlight spans the pressed group; after, the live span.
            let span: RingSpan? = edge.map { RailRing.span(groupSizes: sizes, group: g, edge: $0, fingerY: fingerY, metrics: railMetrics) }
            let firstFlat = span?.firstFlat ?? RailLayout.flatIndex(groupSizes: sizes, group: g, index: 0)
            let lastFlat = span?.lastFlat ?? (firstFlat + sizes[g] - 1)
            if let first = exerciseRow(layout: layout, sizes: sizes, flat: firstFlat),
               let last = exerciseRow(layout: layout, sizes: sizes, flat: lastFlat) {
                // Full-width ring: the tentative membership reads across
                // the whole rows, not under the thumb. Breathing room on
                // all sides; the list's 10 pt top inset keeps the stroke
                // visible even when the span starts at the first row.
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.selected.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Theme.selected, lineWidth: 2)
                    )
                    // Mid-gesture this IS selection (§1a), so it speaks
                    // the selection grammar; the legend is the one place
                    // the word SUPERSET survives, punched through the
                    // stroke on the top edge.
                    .overlay(alignment: .topTrailing) {
                        Text("SUPERSET")
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            .kerning(0.7)
                            .foregroundStyle(Theme.selected)
                            .padding(.horizontal, 6)
                            .background(Theme.background)
                            .offset(y: -6)
                            .padding(.trailing, 12)
                    }
                    .frame(height: last.maxY - first.y + 12)
                    .padding(.horizontal, -8)
                    .offset(y: first.y - 6)
                    .allowsHitTesting(false)
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
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
            let routineExercise = groups[g].sortedExercises[i]
            ExerciseRailRow(routineExercise: routineExercise, role: .solo)
                .padding(.horizontal, 8)
                .frame(height: railRowHeight)
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
        let centerY = fingerY - grabOffset + railRowHeight / 2
        guard let target = RailDrag.nearestTarget(groupSizes: sizes, dragging: (group: g, index: i), fingerY: centerY, metrics: railMetrics) else { return }

        let groups = routine.sortedGroups
        guard groups.indices.contains(g), groups[g].sortedExercises.indices.contains(i) else { return }
        let routineExercise = groups[g].sortedExercises[i]

        switch target {
        case .gap(let gap):
            routine.placeSolo(routineExercise, atGap: gap, context: modelContext)
        case .within(_, let index):
            routine.reorderExercise(routineExercise, toIndex: index)
        }
    }

    private func commitRing(group g: Int, edge: RingEdge, fingerY: Double) {
        let sizes = groupSizes
        guard sizes.indices.contains(g) else { return }
        let span = RailRing.span(groupSizes: sizes, group: g, edge: edge, fingerY: fingerY, metrics: railMetrics)
        guard !span.isNoOp else { return }
        let group = routine.sortedGroups[g]

        for _ in 0..<span.absorbAfter {
            let groups = routine.sortedGroups
            guard let index = groups.firstIndex(where: { $0 === group }),
                  groups.indices.contains(index + 1) else { break }
            routine.mergeSoloGroup(groups[index + 1], direction: -1, context: modelContext)
        }
        for _ in 0..<span.absorbBefore {
            let groups = routine.sortedGroups
            guard let index = groups.firstIndex(where: { $0 === group }),
                  index > 0 else { break }
            routine.mergeSoloGroup(groups[index - 1], direction: 1, context: modelContext)
        }
        for _ in 0..<span.ejectLast {
            guard group.isSuperset, let last = group.sortedExercises.last else { break }
            routine.splitExercise(last, context: modelContext)
        }
        for _ in 0..<span.ejectFirst {
            guard group.isSuperset, let first = group.sortedExercises.first else { break }
            routine.splitExercise(first, placeAbove: true, context: modelContext)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if !routine.groups.isEmpty {
            Button {
                activeSession = WorkoutSession.start(from: routine, context: modelContext)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "play.fill").font(.system(.footnote))
                    Text("Start workout").font(.system(.body, weight: .bold))
                }
                .foregroundStyle(Theme.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
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
            routine.addExerciseInNewGroup(exercise, context: modelContext)
        case .group(let group):
            routine.addExercise(exercise, to: group, context: modelContext)
        }
    }

    private func deleteExercise(_ routineExercise: RoutineExercise, in group: ExerciseGroup) {
        modelContext.delete(routineExercise)
        group.reindexExercises()
        if group.sortedExercises.isEmpty {
            modelContext.delete(group)
            routine.reindexGroups()
        }
    }

    /// The design's DUPE: copy the exercise (with its targets) into a new
    /// solo group directly below this one.
    private func duplicateExercise(_ routineExercise: RoutineExercise, in group: ExerciseGroup) {
        guard let exercise = routineExercise.exercise else { return }

        for later in routine.sortedGroups where later.order > group.order {
            later.order += 1
        }
        let copyGroup = ExerciseGroup(order: group.order + 1, sets: group.sets)
        copyGroup.routine = routine
        modelContext.insert(copyGroup)

        let copy = RoutineExercise(exercise: exercise, order: 0)
        copy.weight = routineExercise.weight
        copy.reps = routineExercise.reps
        copy.repsUpper = routineExercise.repsUpper
        copy.durationSeconds = routineExercise.durationSeconds
        copy.group = copyGroup
        modelContext.insert(copy)
        routine.reindexGroups()
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
    let routineExercise: RoutineExercise
    let role: RailRole
    var rowHeight: Double = 52
    /// Ring-edit mode (#87): the small loop and the expanded full-width
    /// ring are mutually exclusive — the active group's rows drop their
    /// loop drawing while the highlight is up.
    var hideLoop = false

    private var isDuration: Bool {
        routineExercise.exercise?.exerciseType == .duration
    }

    /// "3×15", "3×10 · 5lb", "2×45s" — the condensed target summary.
    private var summary: String {
        let sets = routineExercise.group?.sets ?? 1
        let unit = WeightUnit(rawValue: weightUnitRaw) ?? .lb
        if isDuration {
            let dur = routineExercise.durationSeconds.map { seconds in
                seconds >= 60
                    ? WorkoutMetric.duration.formatted(Double(seconds))
                    : "\(seconds)s"
            } ?? "—"
            return "\(sets)×\(dur)"
        }
        let reps = RepTarget(lower: routineExercise.reps, upper: routineExercise.repsUpper).display
        var text = "\(sets)×\(reps)"
        if let weight = routineExercise.weight {
            text += " · \(WorkoutMetric.weight.formatted(weight))\(unit.symbol)"
        }
        return text
    }

    var body: some View {
        HStack(spacing: 13) {
            RailGlyph(role: hideLoop ? .solo : role, height: rowHeight, dotY: rowHeight / 2)
                .frame(width: 28, height: rowHeight)

            Text(routineExercise.exercise?.name ?? "Unknown")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 6)

            if isDuration {
                Image(systemName: "clock")
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textFaint)
            }
            Text(summary)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(height: rowHeight)
    }
}

/// The rail drawing beside each exercise row, redrawn in v4 §1a: the
/// spine runs SOLID through members (dash means "pending", and only on
/// Today), grouping is a return loop on the rail side at x=3, and at
/// rest the whole glyph draws in the rail's own ink — border for the
/// loop, borderStrong for node strokes — because collapsed it's just a
/// map of the routine's order. Blue appears on the rail only while the
/// ring gesture is live (the highlight in ringHighlight), and in that
/// moment it IS selection. Reading: sets run down the spine; the loop
/// returns you to the top — the A1 B1 A2 B2 rotation made literal.
///
/// Geometry: 28 pt column, spine x=15, loop x=3 (12 pt off the spine,
/// ~7 pt clear of the 10 pt node), quarter curves r≈10 into each node.
/// One up-pointing chevron (5×4.5, round caps) per inter-member gap,
/// centered on the row boundary; the line runs continuously from behind
/// the chevron through its tip, and the 4 pt break sits in FRONT of the
/// tip only — in the direction of travel, never behind.
struct RailGlyph: View {
    let role: RailRole
    let height: CGFloat
    let dotY: CGFloat

    private static let spineX: CGFloat = 15
    private static let loopX: CGFloat = 3

    var body: some View {
        Canvas { context, _ in
            let ink = Theme.border
            let loopStyle = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            let spineX = Self.spineX
            let loopX = Self.loopX

            func vline(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) {
                guard y1 > y0 else { return }
                var path = Path()
                path.move(to: CGPoint(x: x, y: y0))
                path.addLine(to: CGPoint(x: x, y: y1))
                context.stroke(path, with: .color(ink), style: loopStyle)
            }

            /// Quarter curve joining the loop line to a node row: the
            /// control point sits at the corner, reading as r≈10.
            func corner(from: CGPoint, to: CGPoint, control: CGPoint) {
                var path = Path()
                path.move(to: from)
                path.addQuadCurve(to: to, control: control)
                context.stroke(path, with: .color(ink), style: loopStyle)
            }

            /// Up-pointing chevron at this row's TOP boundary; the 4 pt
            /// break above the tip is the previous row's job (it stops
            /// its loop line 3.5 pt short of its bottom edge).
            func chevron() {
                var path = Path()
                path.move(to: CGPoint(x: loopX - 2.5, y: 5))
                path.addLine(to: CGPoint(x: loopX, y: 0.5))
                path.addLine(to: CGPoint(x: loopX + 2.5, y: 5))
                context.stroke(path, with: .color(ink), style: loopStyle)
            }

            // The spine is solid through everything (§1a) — role only
            // decides the loop's slice.
            vline(spineX, 0, height)

            switch role {
            case .solo:
                break
            case .supersetFirst:
                // Loop rejoins the first member's node from below.
                corner(
                    from: CGPoint(x: loopX, y: dotY + 10),
                    to: CGPoint(x: spineX, y: dotY),
                    control: CGPoint(x: loopX, y: dotY)
                )
                vline(loopX, dotY + 10, height - 3.5)
            case .supersetMiddle:
                chevron()
                vline(loopX, 0.5, height - 3.5)
            case .supersetLast:
                // Loop leaves the last member's node and runs up.
                chevron()
                vline(loopX, 0.5, dotY - 10)
                corner(
                    from: CGPoint(x: spineX, y: dotY),
                    to: CGPoint(x: loopX, y: dotY - 10),
                    control: CGPoint(x: loopX, y: dotY)
                )
            }

            // The member dot, drawn last so it sits on the lines.
            let dotRect = CGRect(x: spineX - 5, y: dotY - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: dotRect), with: .color(Theme.background))
            context.stroke(
                Path(ellipseIn: dotRect.insetBy(dx: 1, dy: 1)),
                with: .color(Theme.borderStrong),
                style: StrokeStyle(lineWidth: 2)
            )
        }
    }
}

// MARK: - Routine settings screen (v4 §A: pushed page, facts edited in place)

struct RoutineSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var routine: Routine
    /// Pops the enclosing navigation before the model dies.
    var onDelete: () -> Void
    /// Other routines' schedules feed the day-occupancy dots (#112).
    @Query(sort: \Routine.order) private var allRoutines: [Routine]

    @State private var scheduleMode: Int
    @State private var scheduleDays: Set<Int>
    @State private var scheduleTimes: Int
    @State private var schedulePerDays: Int
    @State private var confirmingDelete = false
    /// Inline drafts (#207 — the rename/notes trays died). Name commits
    /// through Save/submit so #189's duplicate guard can veto; notes
    /// write live like every other field on this autosaving page.
    @State private var nameDraft: String
    @State private var notesDraft: String

    init(routine: Routine, onDelete: @escaping () -> Void) {
        self.routine = routine
        self.onDelete = onDelete
        _nameDraft = State(initialValue: routine.name)
        _notesDraft = State(initialValue: routine.notes ?? "")
        // Seed the editor state from the stored schedule; edits write
        // back through persistSchedule() on every change.
        switch routine.schedule {
        case .unscheduled:
            _scheduleMode = State(initialValue: 0)
            _scheduleDays = State(initialValue: [])
            _scheduleTimes = State(initialValue: 3)
            _schedulePerDays = State(initialValue: 7)
        case .weekdays(let days):
            _scheduleMode = State(initialValue: 1)
            _scheduleDays = State(initialValue: days)
            _scheduleTimes = State(initialValue: 3)
            _schedulePerDays = State(initialValue: 7)
        case .frequency(let times, let perDays):
            _scheduleMode = State(initialValue: 2)
            _scheduleDays = State(initialValue: [])
            _scheduleTimes = State(initialValue: times)
            _schedulePerDays = State(initialValue: perDays)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SheetSectionLabel("NAME")
                        .padding(.top, 24)
                    TextField("Routine name", text: $nameDraft)
                        .font(.system(.footnote))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                        .submitLabel(.done)
                        .onSubmit { commitName() }
                        .accessibilityIdentifier("routineNameField")
                    if nameIsTaken {
                        Text("You already have a routine with this name.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.notes)
                            .padding(.top, 6)
                    }

                    SheetSectionLabel("SCHEDULE")
                        .padding(.top, 24)

                    SegmentedTabs(options: ["Off", "Days", "Pace"], selectedIndex: Binding(
                        get: { scheduleMode },
                        set: { scheduleMode = $0; persistSchedule() }
                    ))

                    if scheduleMode == 1 {
                        dayChips
                            .padding(.top, 8)
                    } else if scheduleMode == 2 {
                        frequencySteppers
                            .popoverTip(PaceAnchorTip())
                            .padding(.top, 8)
                    }

                    if let caption = scheduleCaption {
                        Text(caption)
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 6)
                    }

                    SheetSectionLabel("BETWEEN SETS")
                        .padding(.top, 24)

                    MetricStepperRow(
                        label: "Rest",
                        value: WorkoutMetric.rest.displayText(Double(routine.restSeconds)),
                        identifier: "rest",
                        onDecrement: { routine.restSeconds = Int(WorkoutMetric.rest.decremented(Double(routine.restSeconds))) },
                        onIncrement: { routine.restSeconds = Int(WorkoutMetric.rest.incremented(Double(routine.restSeconds))) }
                    )
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))

                    SheetSectionLabel("NOTES")
                        .padding(.top, 24)

                    // Inline (#207) — the tray was ceremony.
                    TextField("Add notes", text: $notesDraft, axis: .vertical)
                        .font(.system(.footnote))
                        .lineLimit(3...8)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                        .onChange(of: notesDraft) { _, text in
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            routine.notes = trimmed.isEmpty ? nil : trimmed
                        }
                        .accessibilityIdentifier("routineNotesField")
                }
                .padding(.bottom, 30)
            }
        }
        .padding(.horizontal, 16)
        .background(Theme.background)
        .pushedScreenChrome(onBack: { commitName(); dismiss() })
        // The full-width swipe-back pops in UIKit and never reaches
        // onBack — without this, a swipe exit silently dropped an
        // uncommitted rename. Idempotent; guarded so the delete path
        // can't race a write onto a deleted model.
        .onDisappear {
            if !routine.isDeleted { commitName() }
        }
        .toolbar {
            // No Save (#219, killed same day #207 added it): every
            // field commits live and the name commits on any exit, so
            // the page is simply always saved. Delete nests behind
            // "…" — present, not primary.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete routine", role: .destructive) {
                        confirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityIdentifier("routineSettingsMenu")
            }
        }
        .confirmationDialog(
            "Delete \u{201C}\(routine.name)\u{201D}?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete routine", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Logged history is untouched.")
        }
    }

    /// Routine name / "routine settings" — the page title is the
    /// routine, which is exactly what makes onboarding step 3
    /// unambiguous about what it's configuring (§A). Back is the
    /// system toolbar's glass chevron (#198).
    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(routine.name)
                .font(.system(.title, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 2)
            Text("routine settings")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Lowercased names of every OTHER routine — renaming to one of
    /// these is blocked because duplicate names defeat the schedule
    /// matching protections (#189).
    private var takenNames: Set<String> {
        Set(allRoutines.filter { $0 !== routine }.map { $0.name.lowercased() })
    }

    private var nameIsTaken: Bool {
        takenNames.contains(nameDraft.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// #189 semantics inline: a valid draft renames in place; an empty
    /// or taken one quietly reverts to the stored name.
    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !nameIsTaken {
            routine.name = trimmed
        } else {
            nameDraft = routine.name
        }
    }

    // MARK: - Schedule (#83)

    /// Fixed Sunday-first row matching Calendar weekday numbers 1…7.
    private static let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    private var dayChips: some View {
        HStack(spacing: 4) {
            ForEach(Self.mondayFirstWeekdays, id: \.self) { weekday in
                let selected = scheduleDays.contains(weekday)
                VStack(spacing: 4) {
                    Button {
                        if selected {
                            scheduleDays.remove(weekday)
                        } else {
                            scheduleDays.insert(weekday)
                        }
                        persistSchedule()
                    } label: {
                        // Solid selection blue (#210), not green:
                        // scheduling a day is choosing an option; the
                        // due OUTPUT on Today stays green.
                        Text(Self.dayLabels[weekday - 1])
                            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                            .foregroundStyle(selected ? Theme.onSelected : Theme.textSecondary)
                            .frame(width: 44, height: 44)
                            .background(
                                selected ? AnyShapeStyle(Theme.selected) : AnyShapeStyle(Theme.background),
                                in: Circle()
                            )
                            .overlay(Circle().strokeBorder(selected ? Color.clear : Theme.border, lineWidth: 1))
                    }
                    .accessibilityIdentifier("scheduleDay\(weekday)")

                    // 4 pt occupancy dot: another routine lives here.
                    Circle()
                        .fill(occupiedDays.keys.contains(weekday) ? Theme.textFaint : Color.clear)
                        .frame(width: 4, height: 4)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: scheduleDays)
        .sensoryFeedback(.selection, trigger: scheduleDays)
    }

    /// Monday-first calendar weekday numbers, matching the prototype.
    private static let mondayFirstWeekdays = [2, 3, 4, 5, 6, 7, 1]

    /// weekday → another scheduled routine's name occupying that day.
    private var occupiedDays: [Int: String] {
        var result: [Int: String] = [:]
        for other in allRoutines where other !== routine {
            if case .weekdays(let days) = other.schedule.normalized {
                for day in days where result[day] == nil {
                    result[day] = other.name
                }
            }
        }
        return result
    }

    private var frequencySteppers: some View {
        VStack(spacing: 0) {
            MetricStepperRow(
                label: "Sessions",
                value: "\(scheduleTimes)×",
                identifier: "scheduleTimes",
                onDecrement: { scheduleTimes = max(1, scheduleTimes - 1); persistSchedule() },
                onIncrement: { scheduleTimes = min(14, scheduleTimes + 1); persistSchedule() }
            )
            MetricStepperRow(
                label: "Every",
                value: "\(schedulePerDays) days",
                identifier: "schedulePerDays",
                onDecrement: { schedulePerDays = max(1, schedulePerDays - 1); persistSchedule() },
                onIncrement: { schedulePerDays = min(30, schedulePerDays + 1); persistSchedule() }
            )
        }
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    /// §G: only genuinely informative captions survive — the empty-days
    /// prompt died (seven circles under SCHEDULE self-describe), and the
    /// occupancy line renders only while a dot is showing.
    private var scheduleCaption: String? {
        switch scheduleMode {
        case 1:
            if scheduleDays.isEmpty {
                return nil
            }
            if let (day, name) = occupiedExample {
                let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
                return "· = \(name) lives on \(names[day - 1])"
            }
            return "On the marked days; a missed day carries over until you do it."
        case 2:
            // The anchor concept moved to a one-time tip (§G); only the
            // computed interval survives as ambient data.
            let interval = (schedulePerDays + scheduleTimes - 1) / scheduleTimes
            return "\(scheduleTimes)×/\(schedulePerDays)d comes around every ~\(interval) day\(interval == 1 ? "" : "s")."
        default:
            return "No schedule — this routine never appears on Today by itself. Swap it in whenever."
        }
    }

    /// First occupancy example for the caption, preferring dotted days.
    private var occupiedExample: (Int, String)? {
        for weekday in Self.mondayFirstWeekdays {
            if let name = occupiedDays[weekday] {
                return (weekday, name)
            }
        }
        return nil
    }

    private func persistSchedule() {
        switch scheduleMode {
        case 1: routine.schedule = .weekdays(scheduleDays)
        case 2: routine.schedule = .frequency(times: scheduleTimes, perDays: schedulePerDays)
        default: routine.schedule = .unscheduled
        }
    }

}

