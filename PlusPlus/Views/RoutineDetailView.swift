import SwiftUI
import SwiftData
import TipKit
import PlusPlusKit
import Foundation   // sin / pow for the landing-animation easings

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
    /// The first-workout Health primer, raised by the start gate.
    @State private var healthStartRequest: HealthStartRequest?
    @State private var showingRoutineSettings = false
    @State private var showingShareSheet = false
    /// The exercise-detail tray's target, keyed on the RoutineExercise's
    /// stable `uuid` (not the model / its persistentModelID, which would
    /// re-key the open sheet on a background autosave — the flicker).
    @State private var selectedExercise: IdentifiedUUID?
    @State private var railGesture: RailGestureState = .idle
    // Swipe-open state stays on persistentModelID: it's not a flicker
    // source (an id swap just collapses an open swipe), and it avoids a
    // double-optional now that uuid is optional.
    @State private var openSwipeRow: PersistentIdentifier?
    /// The just-formed superset's landing animation (nil at rest). Keyed
    /// by the group's stable id so it survives the commit's reindex; its
    /// `progress` runs 0→1 as the single clock for the field reshape+snap,
    /// the pulse spark, and the loop's blue→gray fade. See
    /// `supersetLandingFX` (spanning FX) and `RailGlyph` (per-row loop).
    @State private var supersetLanding: SupersetLanding?
    /// Monotonic trigger for the landing impact — a single medium "snap"
    /// at the field's deflate (Phase B → C), distinct from the light drag
    /// ticks; `.success` stays reserved for the purple finish.
    @State private var landingTick = 0
    /// Monotonic token identifying the current landing run, so a superseded
    /// run's deferred work (the clock, its completion, the delayed haptic)
    /// bows out instead of clobbering a newer one.
    @State private var landingSeq = 0
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

    /// A superset just formed by a ring-drag: `groupID` is the surviving
    /// container's stable id, `progress` animates 0 (big blue field, loop
    /// vivid) → 1 (field collapsed away, loop settled).
    private struct SupersetLanding: Equatable {
        var groupID: UUID
        var progress: Double
        /// The group was already a superset (≥2) before this landing grew
        /// it — so its rows keep their loop through the reshape.
        var grew: Bool
    }

    var body: some View {
        // Detail renders against a LIVE routine only. Delete flows
        // (RoutineSettingsScreen's onDelete, or a delete elsewhere) flip
        // routine.isDeleted while this screen may still be mounted;
        // collapse to nothing so Observation never re-renders body against
        // a dead model (routine.groups / .sortedGroups would fault — the
        // standing deleted-model-race law), and pop the screen off the
        // stack when it happens. The guard, not any pop timing, is what
        // prevents the crash; the onChange, not a second pop racing the
        // settings pop, is what unwinds the stack.
        Group {
            if routine.isDeleted {
                Color.clear
            } else {
                detailContent
            }
        }
        .onChange(of: routine.isDeleted) { _, deleted in
            if deleted { dismiss() }
        }
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            header

            // Inline in the flow, not a popover (Dave, build-45: the
            // balloon anchored to the rail's top edge read as randomly
            // placed and floated over the first rows). An inline card
            // sits between the facts and the list it explains, and
            // displaces content instead of covering it. Still a
            // SIBLING gate — conditional content must never wrap the
            // rail ScrollView (identity churn mid-gesture, #270).
            SupersetTipInline(
                exerciseCount: routine.sortedGroups.reduce(0) { $0 + $1.sortedExercises.count },
                hasSuperset: routine.sortedGroups.contains(where: \.isSuperset)
            )

            railList
        }
        .background(Theme.background)
        // Operator's view-context: the deepest visible screen reports
        // one compact line (appear-only; the root's re-appear clears it).
        .operatorContext("routines/\(routine.name)")
        // Custom key chrome: back + share/settings as trailing keys, no
        // centered title. The name moved to the body header (Dave,
        // build-78) where it gets full width and wraps instead of
        // truncating; the workload facts already live there (build-48).
        // Share keeps its UIKit sheet (#178).
        .pushedScreenChrome(title: "", onBack: { dismiss() }) {
            if !routine.groups.isEmpty, shareURL != nil {
                HeaderIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Share routine", identifier: "shareRoutineButton") {
                    showingShareSheet = true
                }
            }
            HeaderIconButton(systemImage: "slider.horizontal.3", accessibilityLabel: "Routine settings", identifier: "routineSettingsButton") {
                showingRoutineSettings = true
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
            // Labeled onSelect: the picker gained an onConfigured: param,
            // so an unlabeled trailing closure would backward-match (a
            // deprecation warning, and would misbind to onConfigured under
            // strict forward-scan). Routine building configures via its
            // own detail sheet, so it takes the plain select path.
            ExercisePickerView(filterState: filterState, onSelect: { exercise in
                addExercise(exercise, to: destination)
            })
        }
        .navigationDestination(isPresented: $showingRoutineSettings) {
            RoutineSettingsScreen(routine: routine) {
                // Settings sits ON TOP of this detail, so a delete has two
                // stack levels to unwind. Pop settings now; delete on the
                // next main-actor turn so the settings pop commits first.
                // Detail then pops ITSELF via body's onChange(isDeleted)
                // reacting to the delete — not a second pop in this same
                // transaction, which raced the settings pop into a single
                // pop and stranded the user on the deleted routine's detail.
                showingRoutineSettings = false
                Task { @MainActor in
                    modelContext.delete(routine)
                }
            }
        }
        .sheet(item: $selectedExercise) { ref in
            // Resolve the RoutineExercise from its stable uuid within the
            // live routine graph. Nothing to show if it was deleted.
            if let routineExercise = routine.sortedGroups.flatMap(\.sortedExercises).first(where: { $0.uuid == ref.id }) {
                ExerciseDetailSheet(
                    routine: routine,
                    routineExercise: routineExercise,
                    onAddToSuperset: { group in group.uuid.map { pickerDestination = .group($0) } }
                )
                .presentationDetents([.large])
            }
        }
        .fullScreenCover(item: $activeSession) { session in
            ActiveSessionView(session: session)
        }
        // The one-time Health ask, in front of the first workout start.
        .healthStartPrimer($healthStartRequest)
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

    /// "~40 min · 6 exercises · 18 sets" — the workload facts, now the
    /// body header's top line (moved out of the cramped chrome subtitle,
    /// build-48). Nil until the routine has an exercise.
    private var workloadFacts: String? {
        let exercises = routine.sortedGroups.reduce(0) { $0 + $1.sortedExercises.count }
        guard exercises > 0 else { return nil }
        let sets = routine.sortedGroups.reduce(0) { $0 + $1.sets * $1.sortedExercises.count }
        return "\(routine.estimateText) · \(exercises) exercise\(exercises == 1 ? "" : "s") · \(sets) set\(sets == 1 ? "" : "s")"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The routine name is the screen's heading, below the back
            // key (Dave, build-78): a centered chrome title truncated a
            // long name to "Travel bodyweight…". Here it gets the full
            // width and wraps to a second line instead of clipping.
            Text(routine.name)
                .font(.system(.title, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 4)

            // Facts, not inputs (v4 §A). The chrome carries no title now;
            // the name (above) plus the workload summary and cadence live
            // here at full width. Nothing is tappable — the settings key is
            // the single edit entry.
            if !routine.groups.isEmpty {
                // Workload first — "what is this session" (estimate +
                // counts), full-width so it never truncates the way the
                // chrome subtitle did.
                if let facts = workloadFacts {
                    Text(facts)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 8)
                }
                // Cadence next: schedule value (ink, semibold) then rest
                // as secondary meta.
                (scheduleFactText
                    + Text("  ·  rest \(restText)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary))
                    .padding(.top, workloadFacts == nil ? 8 : 3)

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
                ForEach(Array(groups.enumerated()), id: \.element.uuid) { g, group in
                    ForEach(Array(group.sortedExercises.enumerated()), id: \.element.uuid) { i, routineExercise in
                        railRow(
                            routineExercise, group: group, groupIndex: g, index: i,
                            hideLoop: ringGroup == g,
                            landing: landingParams(groupIndex: g, index: i, layout: layout, sizes: sizes)
                        )
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
            .overlay(alignment: .topLeading) { supersetLandingFX(layout: layout, sizes: sizes) }
            .overlay(alignment: .topLeading) { floatingDragPreview(layout: layout, groups: groups) }
            .animation(.easeOut(duration: 0.16), value: offsets)
            .padding(.top, 10)
            .padding(.leading, 20)
            .padding(.trailing, 14)
            .padding(.bottom, 8)
        }
        .scrollDisabled(railGesture != .idle)
        .sensoryFeedback(.impact(weight: .light), trigger: gestureFeedbackToken)
        .sensoryFeedback(.impact(weight: .medium), trigger: landingTick)
        .onDisappear {
            railGesture = .idle
            // Cancel any in-flight landing: bumping the token invalidates
            // the deferred clock/haptic guards, and clearing the state stops
            // its rendering (the view is going away).
            landingSeq &+= 1
            supersetLanding = nil
        }
        // Routine edits (rail structure, sets, schedule) reach GitHub when you
        // leave the detail. Debounced + dirty-gated, so a no-edit visit is free.
        .syncsProgramOnClose()
    }

    private var activeRingGroup: Int? {
        if case .ring(let g, _, _, _) = railGesture { return g }
        return nil
    }

    /// The + row terminating the rail (#84), at the bottom of the list
    /// where the thumb already is. The KEY is the button (Quiet Arcade:
    /// its plate belongs under the cap alone, not under the rail
    /// glyph), so the glyph sits beside it.
    private var addExerciseRow: some View {
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
            // grammar on a raised key (#224 — dashes belong to
            // pending state, not buttons).
            Button {
                pickerDestination = .newGroup
            } label: {
                Text("Add exercise")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .strokeBorder(Theme.borderStrong)
                    )
            }
            .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
            .accessibilityIdentifier("addExerciseButton")
            Spacer(minLength: 0)
        }
        .frame(height: railRowHeight)
    }

    /// One row: swipe-revealable content with the two long-press zones —
    /// the rail column grabs the ring, the body drags the row.
    private func railRow(_ routineExercise: RoutineExercise, group: ExerciseGroup, groupIndex g: Int, index i: Int, hideLoop: Bool, landing: RailLandingParams) -> some View {
        let height = railRowHeight
        let isDragged: Bool = {
            if case .dragging(let dg, let di, _, _) = railGesture { return dg == g && di == i }
            return false
        }()

        // The rail's reorder + superset live on a UIKit long-press gesture,
        // impossible under VoiceOver / Switch Control. Surface the SAME
        // operations (the ones ExerciseDetailSheet already exposes as buttons)
        // as row custom actions so those users can build/break supersets and
        // reorder without the drag (#164). Bounds mirror the sheet's guards.
        let lastGroup = routine.sortedGroups.count - 1
        var a11yActions: [SwipeRowAction] = []
        if g > 0 {
            a11yActions.append(SwipeRowAction(name: "Move up") { openSwipeRow = nil; moveGroup(g, by: -1) })
        }
        if g < lastGroup {
            a11yActions.append(SwipeRowAction(name: "Move down") { openSwipeRow = nil; moveGroup(g, by: 1) })
        }
        if group.isSuperset {
            a11yActions.append(SwipeRowAction(name: "Move out of superset") {
                openSwipeRow = nil
                routine.splitExercise(routineExercise, context: modelContext)
            })
        } else {
            if g > 0 {
                a11yActions.append(SwipeRowAction(name: "Superset with exercise above") {
                    openSwipeRow = nil
                    routine.mergeSoloGroup(group, direction: -1, context: modelContext)
                })
            }
            if g < lastGroup {
                a11yActions.append(SwipeRowAction(name: "Superset with exercise below") {
                    openSwipeRow = nil
                    routine.mergeSoloGroup(group, direction: 1, context: modelContext)
                })
            }
        }
        a11yActions.append(SwipeRowAction(name: "Duplicate") {
            openSwipeRow = nil
            duplicateExercise(routineExercise, in: group)
        })
        a11yActions.append(SwipeRowAction(name: "Delete") {
            openSwipeRow = nil
            deleteExercise(routineExercise, in: group)
        })

        // Activation is the component's onTap (see the SwipeRevealRow
        // contract): the old row-body and dot-zone onTapGestures were
        // the same latent bug class as the list rows' Buttons — a tap
        // gesture INSIDE content can fire on a reveal drag's release.
        // One component tap now covers the whole row including the dot
        // zone (whose ring gesture stays in the UIKit long-press layer);
        // `enabled: railGesture == .idle` keeps a second finger from
        // opening sheets or closing rows while a rail gesture is live.
        return SwipeRevealRow(
            id: routineExercise.persistentModelID,
            openRow: $openSwipeRow,
            enabled: railGesture == .idle,
            actionsWidth: 116,
            onTap: { selectedExercise = routineExercise.uuid.map(IdentifiedUUID.init) },
            accessibilityActions: a11yActions
        ) {
            ExerciseRailRow(
                routineExercise: routineExercise,
                role: railRole(index: i, of: group),
                rowHeight: railRowHeight,
                hideLoop: hideLoop,
                landing: landing
            )
            .contentShape(Rectangle())
        } actions: {
            HStack(spacing: 0) {
                SwipeActionButton(label: "DUPE", color: Theme.primaryFill, labelColor: Theme.onPrimary) {
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
                    .transition(.opacity.animation(Theme.Anim.standard))
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

    /// Per-row landing inputs for `RailGlyph`, resolved from the active
    /// `SupersetLanding` against the current (post-commit) layout. Inert
    /// unless this group is the one that just formed and has ≥2 members.
    private func landingParams(groupIndex g: Int, index i: Int, layout: RailLayout, sizes: [Int]) -> RailLandingParams {
        guard let landing = supersetLanding,
              routine.sortedGroups.indices.contains(g),
              routine.sortedGroups[g].uuid == landing.groupID,
              sizes.indices.contains(g), sizes[g] > 1,
              let firstRow = layout.row(for: .exercise(group: g, index: 0)),
              let lastRow = layout.row(for: .exercise(group: g, index: sizes[g] - 1)),
              let thisRow = layout.row(for: .exercise(group: g, index: i))
        else { return RailLandingParams() }
        let half = railRowHeight / 2
        return RailLandingParams(
            active: true,
            progress: landing.progress,
            grew: landing.grew,
            firstNodeY: firstRow.y + half,
            lastNodeY: lastRow.y + half,
            rowTopY: thisRow.y
        )
    }

    /// The create → static landing FX that span the whole group (design
    /// handoff 2026-07-12 v2): the selection field's reshape + snap (phases
    /// A/B) and the pulse spark (phase C). Both read the single landing
    /// `progress`; the loop line, chevron reveals and blue→gray fade live
    /// per-row in `RailGlyph`. Uses the POST-commit layout, so the field
    /// band and spark path match the formed group exactly.
    @ViewBuilder
    private func supersetLandingFX(layout: RailLayout, sizes: [Int]) -> some View {
        if let landing = supersetLanding,
           let gf = routine.sortedGroups.firstIndex(where: { $0.uuid == landing.groupID }),
           sizes.indices.contains(gf), sizes[gf] > 1,
           let firstRow = layout.row(for: .exercise(group: gf, index: 0)),
           let lastRow = layout.row(for: .exercise(group: gf, index: sizes[gf] - 1)) {
            let half = railRowHeight / 2
            let firstNodeY = firstRow.y + half
            let lastNodeY = lastRow.y + half
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    SupersetFieldView(
                        progress: landing.progress,
                        width: geo.size.width,
                        fullTop: firstRow.y - 6,
                        fullBottom: lastRow.maxY + 6,
                        firstNodeY: firstNodeY,
                        lastNodeY: lastNodeY
                    )
                    SupersetSparkView(
                        progress: landing.progress,
                        firstNodeY: firstNodeY,
                        lastNodeY: lastNodeY
                    )
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
            }
            .allowsHitTesting(false)
        }
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
        // Captured BEFORE the merges: did this landing grow an existing
        // superset, or form a fresh one? Drives whether the loop is kept
        // through the reshape or revealed.
        let wasExistingSuperset = group.sortedExercises.count > 1

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

        // Absorbing a neighbor formed (or grew) a superset by hand —
        // whoever did that needs neither the how-to nor an
        // introduction to the loop they just drew.
        if span.absorbAfter > 0 || span.absorbBefore > 0 {
            SupersetCreationTip().invalidate(reason: .actionPerformed)
            SupersetLoopTip().invalidate(reason: .actionPerformed)
            // The selection field they drew now collapses into the loop
            // it leaves behind, with a snap to mark the bond forming.
            flashSupersetLanding(group, grew: wasExistingSuperset)
        }
        // An eject is the same dot-drag mechanic in reverse — the
        // how-to is proven found.
        if span.ejectFirst > 0 || span.ejectLast > 0 {
            SupersetCreationTip().invalidate(reason: .actionPerformed)
        }
    }

    /// Drive the create → static landing for a just-formed/grown superset
    /// (design handoff 2026-07-12 v2): one linear clock, `progress` 0→1 over
    /// ~1.3 s, feeds the field reshape+snap, the pulse spark, and the loop's
    /// blue→gray fade. A medium impact snaps at the Phase B → C hand-off.
    private func flashSupersetLanding(_ group: ExerciseGroup, grew: Bool) {
        guard let groupID = group.uuid else { return }
        let seq = landingSeq &+ 1
        landingSeq = seq
        supersetLanding = SupersetLanding(groupID: groupID, progress: 0, grew: grew)
        // Commit the progress-0 frame FIRST (reshape start), then run the
        // clock on the next tick — animating in the same tick as the insert
        // would snap straight to the end (a fresh view has no baseline to
        // interpolate from). `.linear`: the per-phase easings live inside the
        // views, so the master clock must run at wall speed.
        Task { @MainActor in
            guard landingSeq == seq else { return }   // superseded before it started
            // Under Reduce Motion the multi-phase bloom resolves instantly to
            // the settled loop (WCAG 2.3.3); the snap haptic still fires below.
            withAnimation(Theme.Anim.flourish(.linear(duration: SupersetRailGeometry.total / 1000))) {
                supersetLanding?.progress = 1
            } completion: {
                // A newer landing bumps landingSeq and owns the state; only
                // the finishing one clears itself (→ rest render, identical
                // to the fade's end state, so the swap is seamless).
                if landingSeq == seq { supersetLanding = nil }
            }
        }
        // The "snap shut" click lands at the Phase B → C hand-off (~580 ms),
        // not at t=0 — that's the moment the field deflates into the line.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(580))
            guard landingSeq == seq else { return }
            landingTick &+= 1                          // → .sensoryFeedback(.impact(.medium))
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if !routine.groups.isEmpty {
            StartFlashButton(label: "Start workout", height: 52, identifier: "startWorkoutButton") {
                // Fire-time re-check (the flash defers ~0.85 s; see
                // TodayView.start for the failure class).
                guard activeSession == nil, !routine.isDeleted else { return }
                HealthStartGate.begin({
                    guard activeSession == nil, !routine.isDeleted else { return }
                    activeSession = WorkoutSession.start(from: routine, context: modelContext)
                }, orPresent: { healthStartRequest = $0 })
            }
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
        case .group(let uuid):
            guard let group = routine.sortedGroups.first(where: { $0.uuid == uuid }) else { return }
            routine.addExercise(exercise, to: group, context: modelContext)
            // Picking into an existing group is superset creation by
            // another door — same rule as the ring and sheet paths:
            // hand-creation retires both tips.
            SupersetCreationTip().invalidate(reason: .actionPerformed)
            SupersetLoopTip().invalidate(reason: .actionPerformed)
        }
        // Persist the freshly inserted group/exercise. This screen's trays
        // now key on the stable `uuid` (not persistentModelID), so they no
        // longer flicker when the id swaps — this save is belt-and-suspenders
        // (and the honest commit of a durable user action).
        try? modelContext.save()
    }

    private func deleteExercise(_ routineExercise: RoutineExercise, in group: ExerciseGroup) {
        modelContext.delete(routineExercise)
        group.reindexExercises()
        if group.sortedExercises.isEmpty {
            modelContext.delete(group)
            routine.reindexGroups()
        }
    }

    /// Discrete group reorder — the non-gesture path behind the rail's
    /// long-press drag, surfaced as a VoiceOver custom action (#164). Mirrors
    /// ExerciseDetailSheet.moveGroup so both routes reindex identically.
    private func moveGroup(_ index: Int, by delta: Int) {
        var sorted = routine.sortedGroups
        let target = index + delta
        guard sorted.indices.contains(index), sorted.indices.contains(target) else { return }
        sorted.swapAt(index, target)
        for (newOrder, moved) in sorted.enumerated() { moved.order = newOrder }
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
        copy.heartRateTargetData = routineExercise.heartRateTargetData
        copy.group = copyGroup
        modelContext.insert(copy)
        routine.reindexGroups()
        // Permanent id before the duplicated row can be tapped open — an
        // item-keyed tray re-keys and flickers if the id swaps under it on
        // a later autosave (see addExercise for the full mechanism).
        try? modelContext.save()
    }

}

/// Structural gate for the superset tips. One branch renders at a
/// time, which keeps the two tips contextually exclusive by
/// construction: a loop on the rail explains itself; no loop but
/// material to pair teaches the making of one; a single exercise gets
/// neither. TipView renders nothing while TipKit rules its tip out
/// (already shown, invalidated, or not yet due), so most of the time
/// this whole view is empty.
///
/// ⚠️ Identity constraint (#270, still binding): this view's inputs
/// change while routine detail is on screen (the first ring absorb),
/// and each branch is a distinct _ConditionalContent — whatever sits
/// inside is TORN DOWN on every flip. It must stay a SIBLING of the
/// rail ScrollView, never a wrapper around it.
private struct SupersetTipInline: View {
    let exerciseCount: Int
    let hasSuperset: Bool

    var body: some View {
        if hasSuperset {
            TipView(SupersetLoopTip())
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
        } else if exerciseCount >= 2 {
            TipView(SupersetCreationTip())
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
        }
    }
}

/// Where a picked exercise should land: a fresh group at the end, or an
/// existing group (forming a superset).
enum PickerDestination: Identifiable {
    case newGroup
    /// A superset target, keyed on the group's stable `uuid` (not its
    /// persistentModelID, which would re-key the open picker on autosave).
    case group(UUID)

    var id: AnyHashable {
        switch self {
        case .newGroup: AnyHashable("newGroup")
        case .group(let uuid): AnyHashable(uuid)
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

/// Per-row inputs for the create → static landing, resolved from the
/// active `SupersetLanding` against the rail layout. Inert by default.
struct RailLandingParams {
    var active = false
    var progress: Double = 0
    var grew = false
    var firstNodeY: CGFloat = 0
    var lastNodeY: CGFloat = 0
    var rowTopY: CGFloat = 0
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
    /// The create → static landing for this row's group, forwarded to the
    /// glyph. Inert (`isLanding == false`) at rest.
    var landing = RailLandingParams()

    /// "3×15", "3×10 · 5lb", "2×45s", "4×500 m" — the condensed target
    /// summary, speaking each block's WORK metric (flexible metrics).
    private var summary: String {
        let sets = routineExercise.group?.sets ?? 1
        let unit = WeightUnit(rawValue: weightUnitRaw) ?? .lb
        let profile = routineExercise.exercise?.metricProfile ?? .weightReps
        if profile.tracksReps {
            let reps = RepTarget(lower: routineExercise.reps, upper: routineExercise.repsUpper).display
            var text = "\(sets)×\(reps)"
            if let weight = routineExercise.weight {
                text += " · \(WorkoutMetric.weight.formatted(weight))\(unit.symbol)"
            }
            return text
        }
        let driver = profile.driver { routineExercise.target($0) }
        if driver == .duration {
            let dur = routineExercise.durationSeconds.map { DurationTape.label(for: $0) } ?? "—"
            return "\(sets)×\(dur)"
        }
        return "\(sets)×" + driver.displayText(
            routineExercise.target(driver),
            weightUnit: unit,
            distanceUnit: profile.distanceUnit
        )
    }

    var body: some View {
        HStack(spacing: 13) {
            RailGlyph(
                role: hideLoop ? .solo : role,
                height: rowHeight,
                dotY: rowHeight / 2,
                isLanding: !hideLoop && landing.active,
                landingProgress: landing.progress,
                landingGrew: landing.grew,
                groupFirstNodeY: landing.firstNodeY,
                groupLastNodeY: landing.lastNodeY,
                rowTopY: landing.rowTopY
            )
            .frame(width: 28, height: rowHeight)
            // The rail glyph is a Canvas drawing of the order/superset spine;
            // its meaning is spoken via the row's accessibilityValue below.
            .accessibilityHidden(true)

            Text(routineExercise.exercise?.name ?? "Unknown")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 6)

            // The clock marks time-driven blocks (a plank, a 20:00
            // piece) — distance/calorie work speaks its unit already.
            if routineExercise.exercise?.metricProfile.contains(.duration) == true,
               !(routineExercise.exercise?.metricProfile.tracksReps ?? false) {
                Image(systemName: "clock")
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textFaint)
            }
            Text(summary)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(minHeight: rowHeight)
        // One coherent read per row (name + target), with the superset
        // grouping the Canvas draws spoken as a value (#164). Rail rows carry
        // no test identifiers, so combining is safe (testing.md).
        .accessibilityElement(children: .combine)
        .accessibilityValue(routineExercise.group?.isSuperset == true ? "In a superset" : "")
    }
}

/// The rail drawing beside each exercise row: the spine runs SOLID through
/// members, grouping is a return loop on the rail side at x=3. The spine
/// and node strokes stay neutral (border / borderStrong) — they're the
/// order map. The LOOP + chevrons are the superset mark: they REST in an
/// opaque warm gray (`supersetLoop`) so a bound block reads as structure,
/// and turn the vivid selection blue only during the create animation
/// (design handoff 2026-07-12 v2). Reading: sets run down the spine; the
/// loop returns you to the top — the A1 B1 A2 B2 rotation made literal.
///
/// Geometry: 28 pt column, spine x=15, loop x=3 (12 pt off the spine,
/// ~7 pt clear of the 10 pt node), quarter curves r≈10 into each node.
/// One up-pointing chevron (5×4.5, round caps) per inter-member gap,
/// centered on the row boundary; the line runs continuously from behind
/// the chevron through its tip, and the 4 pt break sits in FRONT of the
/// tip only — in the direction of travel, never behind.
///
/// The create → static landing (see `flashSupersetLanding`) runs off one
/// linear clock, `landingProgress`; this glyph reads it (Animatable, so
/// the Canvas redraws each frame) to fade the loop in during the snap,
/// reveal each chevron as the pulse spark passes, and crossfade the whole
/// loop from blue to its settled gray. At rest (`isLanding == false`) it's
/// just the gray loop with every chevron shown.
struct RailGlyph: View, Animatable {
    let role: RailRole
    let height: CGFloat
    let dotY: CGFloat
    /// Landing animation for this glyph's GROUP. `isLanding` gates it;
    /// `landingProgress` (0→1, linear over ~1.3 s) is the shared clock
    /// every phase reads. The Ys are this row's node-top boundary and the
    /// group's first/last node centres in rail space — for the spark's
    /// per-row chevron reveal. Only `landingProgress` changes per frame.
    var isLanding = false
    var landingProgress: Double = 0
    /// True when the landing GREW an existing superset (vs formed a fresh
    /// one from solos). A grow already shows a settled gray loop, so the
    /// reshape KEEPS it rather than blanking it (which would wink the loop
    /// out for ~260 ms); a fresh pair has nothing to keep and reveals in.
    var landingGrew = false
    var groupFirstNodeY: CGFloat = 0
    var groupLastNodeY: CGFloat = 0
    var rowTopY: CGFloat = 0

    /// `landingProgress` is the animatable channel: a Canvas draws
    /// imperatively and SwiftUI won't re-run a plain View's body per frame,
    /// so conforming makes it interpolate the clock and redraw each step.
    var animatableData: Double {
        get { landingProgress }
        set { landingProgress = newValue }
    }

    private static let spineX: CGFloat = 15
    private static let loopX: CGFloat = 3

    var body: some View {
        Canvas { context, _ in
            let spineX = Self.spineX
            let loopX = Self.loopX
            let loopStyle = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            let look = loopLook()

            // Spine — the order line, neutral, solid through every row.
            var spine = Path()
            spine.move(to: CGPoint(x: spineX, y: 0))
            spine.addLine(to: CGPoint(x: spineX, y: height))
            context.stroke(spine, with: .color(Theme.border), style: loopStyle)

            // Loop + chevrons — the superset mark. Drawn in a sub-context
            // whose opacity carries the snap fade-in (alpha 0 = not drawn).
            if role != .solo, look.alpha > 0 {
                var lctx = context
                lctx.opacity = look.alpha
                let ink = look.ink

                func vline(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) {
                    guard y1 > y0 else { return }
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: y0))
                    p.addLine(to: CGPoint(x: x, y: y1))
                    lctx.stroke(p, with: .color(ink), style: loopStyle)
                }
                func corner(_ from: CGPoint, _ to: CGPoint, _ control: CGPoint) {
                    var p = Path()
                    p.move(to: from)
                    p.addQuadCurve(to: to, control: control)
                    lctx.stroke(p, with: .color(ink), style: loopStyle)
                }
                // Up-chevron at this row's TOP boundary. `look.chevron`
                // decides whether it shows, and whether it flares brighter
                // the instant the pulse spark passes it.
                func chevron() {
                    guard look.chevron != .hidden else { return }
                    var p = Path()
                    p.move(to: CGPoint(x: loopX - 2.5, y: 5))
                    p.addLine(to: CGPoint(x: loopX, y: 0.5))
                    p.addLine(to: CGPoint(x: loopX + 2.5, y: 5))
                    if look.chevron == .flare {
                        lctx.stroke(p, with: .color(Theme.supersetFlare), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    } else {
                        lctx.stroke(p, with: .color(ink), style: loopStyle)
                    }
                }

                switch role {
                case .solo:
                    break
                case .supersetFirst:
                    corner(CGPoint(x: loopX, y: dotY + 10), CGPoint(x: spineX, y: dotY), CGPoint(x: loopX, y: dotY))
                    vline(loopX, dotY + 10, height - 3.5)
                case .supersetMiddle:
                    chevron()
                    vline(loopX, 0.5, height - 3.5)
                case .supersetLast:
                    chevron()
                    vline(loopX, 0.5, dotY - 10)
                    corner(CGPoint(x: spineX, y: dotY), CGPoint(x: loopX, y: dotY - 10), CGPoint(x: loopX, y: dotY))
                }
            }

            // Member dot — drawn last, over the lines, always neutral; a
            // subtle scale pop as the group forms.
            let r = 5 * look.nodePop
            let dotRect = CGRect(x: spineX - r, y: dotY - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: dotRect), with: .color(Theme.background))
            context.stroke(
                Path(ellipseIn: dotRect.insetBy(dx: 1, dy: 1)),
                with: .color(Theme.borderStrong),
                style: StrokeStyle(lineWidth: 2)
            )
        }
    }

    private enum Chevron { case hidden, shown, flare }
    private struct Look { var ink: Color; var alpha: Double; var chevron: Chevron; var nodePop: CGFloat }

    /// This frame's loop appearance, from the shared landing clock.
    private func loopLook() -> Look {
        let gray = Theme.supersetLoop
        let blue = Theme.selected
        guard isLanding else { return Look(ink: gray, alpha: 1, chevron: .shown, nodePop: 1) }

        let g = landingProgress
        let fA = SupersetRailGeometry.fA, fB = SupersetRailGeometry.fB, fC = SupersetRailGeometry.fC
        func eo(_ t: Double) -> Double { let c = min(max(t, 0), 1); return 1 - pow(1 - c, 3) }
        func clamp(_ t: Double) -> Double { min(max(t, 0), 1) }

        if g < fA {
            // Reshape. A fresh pair has no loop yet (draw nothing); GROWING
            // an existing superset keeps its settled gray loop so it doesn't
            // wink out under the morphing field.
            return landingGrew
                ? Look(ink: gray, alpha: 1, chevron: .shown, nodePop: 1)
                : Look(ink: blue, alpha: 0, chevron: .hidden, nodePop: 1)
        } else if g < fB {
            // Snap. Fresh: the line fades IN blue, chevrons still hidden.
            // Grow: the visible gray line crossfades UP to blue (no fade-in),
            // chevrons already shown. The node pops in both.
            let p = (g - fA) / (fB - fA)
            let snap = clamp((p - 0.15) / 0.85)
            let pop = 1 + max(0, sin(clamp((snap - 0.35) / 0.5) * .pi)) * 0.22
            return landingGrew
                ? Look(ink: gray.mix(with: blue, by: eo(snap)), alpha: 1, chevron: .shown, nodePop: CGFloat(pop))
                : Look(ink: blue, alpha: eo(snap), chevron: .hidden, nodePop: CGFloat(pop))
        } else if g < fC {
            // Pulse: full blue; the spark (bottom → top) flares each chevron
            // as it passes. Fresh reveals them progressively; a grow's are
            // already shown, so they only flare.
            let s = eo((g - fB) / (fC - fB))
            let sparkY = SupersetRailGeometry.pulsePoint(s, firstNodeY: groupFirstNodeY, lastNodeY: groupLastNodeY).y
            let flaring = abs(sparkY - rowTopY) < 18
            let chev: Chevron = flaring ? .flare : ((landingGrew || sparkY <= rowTopY + 6) ? .shown : .hidden)
            return Look(ink: blue, alpha: 1, chevron: chev, nodePop: 1)
        } else {
            // Fade: the whole loop crossfades blue → settled gray.
            let f = eo((g - fC) / (1 - fC))
            return Look(ink: blue.mix(with: gray, by: f), alpha: 1, chevron: .shown, nodePop: 1)
        }
    }
}

/// Shared timing + path math for the superset landing (design handoff
/// 2026-07-12 v2). One linear clock (`landingProgress` 0→1 over ~1.3 s)
/// runs four phases — Reshape, Snap, Pulse, Fade — and every landing view
/// reads these to place its own piece against the same wall time.
private enum SupersetRailGeometry {
    static let total: Double = 1300                       // ms
    static let fA = 260.0 / total                         // reshape ends
    static let fB = (260.0 + 320.0) / total               // snap ends
    static let fC = (260.0 + 320.0 + 420.0) / total       // pulse ends; fade → 1.0

    static let loopX: CGFloat = 3
    static let nodeX: CGFloat = 15

    /// The pulse spark's point along the ACTUAL loop path, s: 0 (bottom /
    /// last node) → 1 (top / first node): out of the last node on its
    /// quarter curve, up the straight line, into the first node's curve —
    /// so the glow hugs the curves rather than running a bare vertical.
    static func pulsePoint(_ s: Double, firstNodeY: CGFloat, lastNodeY: CGFloat) -> CGPoint {
        let dotFirst = firstNodeY, dotLast = lastNodeY
        let lineTop = dotFirst + 10, lineBot = dotLast - 10
        func quad(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
            let mt = 1 - t
            return CGPoint(
                x: mt * mt * p0.x + 2 * mt * t * c.x + t * t * p1.x,
                y: mt * mt * p0.y + 2 * mt * t * c.y + t * t * p1.y
            )
        }
        if s < 0.14 {
            return quad(CGPoint(x: nodeX, y: dotLast), CGPoint(x: loopX, y: dotLast), CGPoint(x: loopX, y: lineBot), CGFloat(s / 0.14))
        } else if s < 0.86 {
            let t = CGFloat((s - 0.14) / 0.72)
            return CGPoint(x: loopX, y: lineBot + (lineTop - lineBot) * t)
        } else {
            return quad(CGPoint(x: loopX, y: lineTop), CGPoint(x: loopX, y: dotFirst), CGPoint(x: nodeX, y: dotFirst), CGFloat((s - 0.86) / 0.14))
        }
    }
}

/// The selection field's landing move (phases A + B). It REShapes onto the
/// loop-to-be with the right edge HELD at full width, then the right edge
/// sweeps left in one monotonic ease, deflating into the loop line — so the
/// snap is the right edge's one and only move (no mid-way seam). Animatable
/// so the shape recomputes each frame off the shared clock.
private struct SupersetFieldView: View, Animatable {
    var progress: Double
    let width: CGFloat        // rail content width — the full-width right edge
    let fullTop: CGFloat
    let fullBottom: CGFloat
    let firstNodeY: CGFloat
    let lastNodeY: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let g = progress
        let fA = SupersetRailGeometry.fA, fB = SupersetRailGeometry.fB
        func eo(_ t: Double) -> Double { let c = min(max(t, 0), 1); return 1 - pow(1 - c, 3) }
        func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

        let fullLeft: CGFloat = -8, fullRight = width + 8
        let alignLeft: CGFloat = 2

        var left = fullLeft, right = fullRight, top = fullTop, bottom = fullBottom
        var tlr: CGFloat = 12, blr: CGFloat = 12, trr: CGFloat = 12, brr: CGFloat = 12
        var fillOpacity = 0.16
        var visible = true

        if g < fA {
            // Reshape: top/bottom/left edges + left corners settle onto the
            // loop; the right edge is held at full width.
            let p = eo(g / fA)
            left = lerp(fullLeft, alignLeft, p)
            top = lerp(fullTop, firstNodeY, p)
            bottom = lerp(fullBottom, lastNodeY, p)
            tlr = lerp(12, 11, p); blr = lerp(12, 11, p)
        } else if g < fB {
            // Snap: the right edge sweeps left onto the line; fill fades;
            // right corners tighten 12 → 4.
            let p = (g - fA) / (fB - fA)
            let er = 1 - pow(1 - p, 2.2)                   // fast, then a gentle settle
            left = alignLeft; top = firstNodeY; bottom = lastNodeY
            right = lerp(fullRight, alignLeft + 2, er)
            tlr = 11; blr = 11
            trr = lerp(12, 4, p); brr = lerp(12, 4, p)
            fillOpacity = 0.16 * (1 - min(max((er - 0.2) / 0.8, 0), 1))
        } else {
            visible = false
        }

        let shape = UnevenRoundedRectangle(topLeadingRadius: tlr, bottomLeadingRadius: blr, bottomTrailingRadius: brr, topTrailingRadius: trr)
        return shape
            .fill(Theme.selected.opacity(fillOpacity))
            .overlay(shape.strokeBorder(Theme.selected, lineWidth: 2))
            .frame(width: max(0, right - left), height: max(0, bottom - top), alignment: .topLeading)
            .opacity(visible ? 1 : 0)
            .offset(x: left, y: top)
    }
}

/// The pulse spark (phase C): a soft, low-intensity additive bloom that
/// rides the loop path bottom → top. Its chevron reveals live in RailGlyph;
/// this draws only the travelling glow.
private struct SupersetSparkView: View, Animatable {
    var progress: Double
    let firstNodeY: CGFloat
    let lastNodeY: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            let g = progress
            let fB = SupersetRailGeometry.fB, fC = SupersetRailGeometry.fC
            guard g >= fB, g < fC else { return }
            func eo(_ t: Double) -> Double { let c = min(max(t, 0), 1); return 1 - pow(1 - c, 3) }
            let s = eo((g - fB) / (fC - fB))
            let pt = SupersetRailGeometry.pulsePoint(s, firstNodeY: firstNodeY, lastNodeY: lastNodeY)
            let glow = Gradient(stops: [
                .init(color: Theme.supersetFlare.opacity(0.42), location: 0),
                .init(color: Theme.selected.opacity(0.16), location: 0.5),
                .init(color: Theme.selected.opacity(0), location: 1),
            ])
            var gctx = context
            gctx.blendMode = .plusLighter
            gctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - 10, y: pt.y - 10, width: 20, height: 20)),
                with: .radialGradient(glow, center: pt, startRadius: 0, endRadius: 10)
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
    @State private var showingRestScrubber = false
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
                            .padding(.top, 8)
                    }

                    if let caption = scheduleCaption {
                        Text(caption)
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 6)
                    }

                    // Pace's anchor semantics are permanent copy (the
                    // one-time tip died in the TipKit rework): the
                    // concept is load-bearing every time the mode is
                    // chosen, not a first-encounter surprise. Generic
                    // wording — the caption above already interpolates
                    // the user's live pace, and a hardcoded example
                    // would mismatch it.
                    if scheduleMode == 2 {
                        Text("Pace counts from your last completion, not the calendar week — miss a day and nothing stacks up.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 4)
                    }

                    SheetSectionLabel("BETWEEN SETS")
                        .padding(.top, 24)

                    MetricStepperRow(
                        label: "Rest",
                        value: WorkoutMetric.rest.displayText(Double(routine.restSeconds)),
                        identifier: "rest",
                        onTapValue: { showingRestScrubber = true },
                        onDecrement: { routine.restSeconds = Int(WorkoutMetric.rest.decremented(Double(routine.restSeconds))) },
                        onIncrement: { routine.restSeconds = Int(WorkoutMetric.rest.incremented(Double(routine.restSeconds))) }
                    )
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                    .sheet(isPresented: $showingRestScrubber) {
                        // Tap-to-pick parity with the block-level rest row
                        // (2026-07-15) — this row had only the ±15 s stepper.
                        MetricWheelSheet(
                            metric: .rest,
                            value: Binding(
                                get: { Double(routine.restSeconds) },
                                set: { routine.restSeconds = Int(($0 ?? Double(routine.restSeconds)).rounded()) }
                            )
                        )
                    }

                    SheetSectionLabel("BETWEEN EXERCISES")
                        .padding(.top, 24)

                    MetricStepperRow(
                        label: "Transition",
                        value: WorkoutMetric.transition.displayText(Double(routine.transitionSeconds)),
                        identifier: "transition",
                        onDecrement: { routine.transitionSeconds = Int(WorkoutMetric.transition.decremented(Double(routine.transitionSeconds))) },
                        onIncrement: { routine.transitionSeconds = Int(WorkoutMetric.transition.incremented(Double(routine.transitionSeconds))) }
                    )
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))

                    // Rest is for a new round of the same block (#369) —
                    // switching stations gets this shorter pause.
                    Text("Switching to a different exercise (or a superset partner) uses this instead of rest. 0 skips the countdown.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 6)

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
        // A static "Routine settings" heading (Dave, build-78): the
        // routine's name was redundant with the editable NAME field right
        // below, and truncated when long. No Save (#219): every field
        // commits live and the name commits on any exit, so the page is
        // simply always saved. Delete nests behind "…" — present, not
        // primary.
        .pushedScreenChrome(title: "Routine settings", onBack: { commitName(); dismiss() }) {
            HeaderMenuKey(systemImage: "ellipsis", accessibilityLabel: "Routine options", identifier: "routineSettingsMenu") {
                Button("Delete routine", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        // The full-width swipe-back pops in UIKit and never reaches
        // onBack — without this, a swipe exit silently dropped an
        // uncommitted rename. Idempotent; guarded so the delete path
        // can't race a write onto a deleted model.
        .onDisappear {
            if !routine.isDeleted { commitName() }
        }
        // A centered alert, not a confirmationDialog: triggered from the
        // "…" menu on this pushed screen, the dialog adapted to a
        // popover that floated anchored to nothing near the tab bar
        // (same class as #204's floating catalog offer). An alert
        // presents centered and predictably, matching the custom
        // exercise delete confirm in CatalogDetailViews.
        .alert(
            "Delete \u{201C}\(routine.name)\u{201D}?",
            isPresented: $confirmingDelete
        ) {
            Button("Delete routine", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Logged history is untouched.")
        }
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
                        // due OUTPUT on Today stays green. 34 pt visual
                        // (Quiet Arcade) inside the 44 pt hit target.
                        Text(Self.dayLabels[weekday - 1])
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .foregroundStyle(selected ? Theme.onSelected : Theme.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(
                                selected ? AnyShapeStyle(Theme.selected) : AnyShapeStyle(Theme.background),
                                in: Circle()
                            )
                            .overlay(Circle().strokeBorder(selected ? Color.clear : Theme.border, lineWidth: 1))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
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
        .animation(Theme.Anim.selection, value: scheduleDays)
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
            // The computed interval as ambient data; the anchor
            // semantics live in the permanent footnote below this.
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

