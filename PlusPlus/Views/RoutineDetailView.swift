import SwiftUI
import SwiftData
import TipKit
import PlusPlusKit
import UIKit        // UIFont metrics: where the rail node sits on the name's first line
import Foundation   // sin / pow for the landing-animation easings

/// Routine detail, v2 (#61): a compact program view — meta line with
/// estimated time and rest, exercise rows on a rail with supersets drawn
/// as a stadium loop, swipe actions, and a pinned Start/Add bar. Editing
/// a row happens in ExerciseDetailSheet (#62).
struct RoutineDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var routine: Routine

    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    /// Newest first — `RoutineLedger` resolves "last time" as the first
    /// session containing the exercise, so the order is load-bearing.
    @Query(sort: \WorkoutSession.endedAt, order: .reverse) private var sessions: [WorkoutSession]
    @AppStorage(WeightUnitSetting.key) private var detailWeightUnitRaw: String = WeightUnit.lb.rawValue
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    /// Active-kit gear names, so the header's gear capsules can amber-flag a
    /// piece the kit lacks (flag-don't-hide, #113).
    private var availableEquipmentNames: Set<String> {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)?.memberNames ?? []
    }

    /// Resolve a header kit chip's name to its piece for the detail sheet —
    /// a direct fetch (the `ModelContext.routine(uuid:)` pattern), so this
    /// view carries no standing all-equipment query for one tap. Kit
    /// membership is a set of `Equipment` objects, so an in-kit name always
    /// resolves; nil (a vanished piece) just means no sheet.
    private func equipment(named name: String) -> Equipment? {
        let descriptor = FetchDescriptor<Equipment>(predicate: #Predicate { $0.name == name })
        return (try? modelContext.fetch(descriptor))?.first
    }

    @State private var pickerDestination: PickerDestination?
    /// The slot to reopen if a browse-all swap is CANCELLED (#508, b27).
    /// "Browse all exercises" is a detour inside the swap flow, not a new
    /// errand: backing out of the catalog used to drop you on routine
    /// detail with the sheet you started from gone, so the way back to the
    /// exercise you were configuring was to find and tap it again. Set when
    /// the swap picker opens, cleared the moment a pick lands.
    @State private var swapReturnTarget: IdentifiedUUID?
    /// The slot a VoiceOver "Delete" action is asking about (#508, Q22-B +
    /// review). The visible Remove gained a confirm; the a11y action is its
    /// closest analogue — one activation, no gesture to think twice during —
    /// so it routes through the same question. The SWIPE keeps its
    /// no-confirm directness: a two-stage drag is its own confirmation.
    @State private var confirmingRailDelete: RailDeleteTarget?
    @State private var activeSession: WorkoutSession?
    /// The first-workout Health primer, raised by the start gate.
    @State private var healthStartRequest: HealthStartRequest?
    @State private var showingRoutineSettings = false
    @State private var showingShareSheet = false
    /// The schedule tray, raised by the header's schedule row.
    @State private var showingScheduleTray = false
    /// The merged rest + transition tray, raised by the header's pauses row.
    @State private var showingPausesTray = false
    /// A piece the active kit HAS, tapped in the header: its own detail
    /// screen (membership toggle, config, cross-links). A piece the kit
    /// lacks opens the resolve sheet instead (`resolveTarget`).
    @State private var kitDetailTarget: Equipment?
    /// The estimate column's width. Scaled so the spec table's labels start
    /// at the same place at every Dynamic Type size.
    @ScaledMetric(relativeTo: .body) private var estimateColumnWidth: Double = 104
    /// The equipment-resolve sheet's target (an equipment name not in the
    /// active kit), raised by tapping an amber gear chip in the header.
    @State private var resolveTarget: ResolveTarget?
    /// The exercise-detail tray's target, keyed on the RoutineExercise's
    /// stable `uuid` (not the model / its persistentModelID, which would
    /// re-key the open sheet on a background autosave — the flicker).
    @State private var selectedExercise: IdentifiedUUID?
    @State private var railGesture: RailGestureState = .idle
    // Swipe-open state stays on persistentModelID: it's not a flicker
    // source (an id swap just collapses an open swipe), and it avoids a
    // double-optional now that uuid is optional.
    @State private var openSwipeRow: SwipeRevealOpen<PersistentIdentifier>?
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
    /// Rows size to their CONTENT (2026-07-30, Dave's pick from the design
    /// round — the honest fix 2026-07-29 named and deferred): a one-line
    /// name no longer pays a two-line name's slot, so the ragged gaps the
    /// uniform 76 pt slot left between short and wrapped rows are gone.
    /// `railRowHeights(width:ledger:)` computes each row from UIFont
    /// metrics — pure reads, never a layout-time state write — and
    /// `RailLayout.build(rowHeights:)` gives the gestures the same
    /// geometry the VStack renders. This floor is the pre-2026-07-29 row
    /// height, proven against the loop drawing and the swipe targets.
    @ScaledMetric(relativeTo: .body) private var railRowMinHeight: Double = 52
    /// The add-exercise terminus keeps the old uniform height — a raised
    /// key wants air, and it is not a content row.
    @ScaledMetric(relativeTo: .body) private var addRowHeight: Double = 76
    /// Air under a row's text block, before the next row begins.
    @ScaledMetric(relativeTo: .body) private var railRowBottomInset: Double = 14
    /// ONE width for the run columns AND the pinned headings over them —
    /// a heading and the thing it heads share their constants or they
    /// drift the moment either is tuned (device pass, 2026-07-29).
    @ScaledMetric(relativeTo: .caption) private var runColumnWidth: Double = 58

    /// How far a rail row's text sits below the row's top edge.
    @ScaledMetric(relativeTo: .body) private var railTextTopInset: Double = 9

    /// Where a node sits inside its row: the centre of the exercise name's
    /// FIRST line, not the middle of the row.
    ///
    /// ⚠️ It lives HERE, not in `ExerciseRailRow`, because the superset
    /// landing FX place their field band and spark against the same nodes
    /// (`supersetLandingFX`, `landingParams`). Those read `railRowHeight / 2`
    /// while the glyph read its own constant, so moving the node off the row's
    /// middle silently left the landing animation anchored where the node used
    /// to be. One number, one owner.
    private var railNodeY: CGFloat {
        CGFloat(railTextTopInset) + UIFont.preferredFont(forTextStyle: .body).lineHeight / 2
    }

    /// Per-row heights in the grouped shape `RailLayout.build(rowHeights:)`
    /// takes, computed from the same UIFont metrics the rows render with —
    /// never measured back from layout, which would mean a state write and
    /// the morph law. The row's shape: `textTopInset`, then the taller of
    /// the name block (1 or 2 lines of scaled semibold body) and the ledger
    /// block (1 or 2 caption-mono lines, seated on the name's first
    /// baseline), then `railRowBottomInset`; floored at the proven 52.
    ///
    /// ⚠️ Must walk the SAME rows `railRows` renders — every
    /// `sortedExercises` entry, nil-exercise ones included — or the gesture
    /// layout and the VStack disagree row by row.
    private func railRowHeights(width: Double, ledger: [String: RoutineLedgerRow]) -> [[Double]] {
        let nameBase = UIFont.preferredFont(forTextStyle: .body)
        let nameFont = UIFont.systemFont(ofSize: nameBase.pointSize, weight: .semibold)
        let captionBase = UIFont.preferredFont(forTextStyle: .caption1)
        let captionFont = UIFont.monospacedSystemFont(ofSize: captionBase.pointSize, weight: .regular)
        // The rows stack's own paddings, then the row's fixed columns:
        // glyph 28 + 13 spacing, two run columns each behind a 13 gap.
        let rowWidth = width - 12 - 14
        let baseNameWidth = rowWidth - 28 - 13 - (runColumnWidth + 13) * 2

        return routine.sortedGroups.map { group in
            group.sortedExercises.map { entry in
                let profile = entry.exercise?.metricProfile
                let hasClock = profile?.contains(.duration) == true
                    && !(profile?.tracksReps ?? false)
                let nameWidth = baseNameWidth - (hasClock ? captionFont.lineHeight + 13 : 0)
                let name = entry.exercise?.name ?? "Unknown"
                // Measured 2 pt narrow so a name at the exact wrap boundary
                // counts as two lines — over-measuring costs a few points of
                // air, under-measuring clips the second line.
                let bounds = (name as NSString).boundingRect(
                    with: CGSize(width: max(10, nameWidth - 2), height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: nameFont],
                    context: nil
                )
                let nameLines = bounds.height > nameFont.lineHeight * 1.5 ? 2.0 : 1.0
                let row = entry.uuid.flatMap { ledger[$0.uuidString] }
                let ledgerLines = Double(max(
                    ExerciseRailRow.printedLines(row?.target ?? []).count,
                    ExerciseRailRow.printedLines(row?.prev ?? []).count
                ))
                let nameBlock = nameLines * nameFont.lineHeight
                // The ledger's first line seats on the name's first baseline,
                // so its block hangs from the two fonts' ascender difference.
                let ledgerBlock = max(0, nameFont.ascender - captionFont.ascender)
                    + ledgerLines * captionFont.lineHeight
                return max(railRowMinHeight, railTextTopInset + max(nameBlock, ledgerBlock) + railRowBottomInset)
            }
        }
    }

    /// Target-vs-prev for every exercise, keyed by the row id the rail
    /// already uses.
    ///
    /// ⚠️ Read ONCE in `railList` and threaded down, never touched per
    /// row: resolving prev walks the session history, so a per-row read
    /// would walk it once per exercise on every render.
    private var ledgerByID: [String: RoutineLedgerRow] {
        let unit = WeightUnit(rawValue: detailWeightUnitRaw) ?? .lb
        let rows = RoutineLedger.rows(for: routine, sessions: sessions, weightUnit: unit)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }

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
        // ⚠️ A PURE width read, and since `ScopeSegmentedControl`'s bar row was
        // deleted (2026-08-05) this is the app's live exemplar of one: the
        // value goes straight into this render's row heights and is never
        // written to state — `onScrollGeometryChange`/`PreferenceKey` here
        // would break the search-role morph (nav-diag 4e).
        GeometryReader { geo in
            railList(width: geo.size.width)
        }
        .background(Theme.background)
        // Feed the creation tip's display rule from live structure (the
        // popover attachment on the first rail row stays unconditional;
        // TipKit decides). task(id:) re-fires whenever eligibility flips.
        .task(id: supersetTipEligible) {
            SupersetCreationTip.canPair = supersetTipEligible
        }
        // Operator's view-context: the deepest visible screen reports
        // one compact line (appear-only; the root's re-appear clears it).
        .operatorContext("routines/\(routine.name)")
        // Custom key chrome: back + share/settings as trailing keys, no
        // centered title. The name moved to the body header (Dave,
        // build-78) where it gets full width and wraps instead of
        // truncating; the workload facts already live there (build-48).
        // Share keeps its UIKit sheet (#178).
        // ⚠️ Routine detail wears the SYSTEM navigation bar with a LARGE
        // title (Dave, 2026-07-29), not `pushedScreenChrome`. That is what
        // buys the native collapse the tab roots have: the name sits large at
        // the top and walks up into the bar, centred and small, as you
        // scroll. It is free and it writes no state, so it stays clear of the
        // morph law — every hand-rolled version needs the scroll offset, and
        // reading that means `onScrollGeometryChange` or a `PreferenceKey`,
        // which is exactly what breaks the search-role morph.
        //
        // Two deliberate departures come with it. The surface law says a
        // pushed detail screen clears its chrome title and leads the body
        // with a large left header; this screen no longer does, so its name
        // is single-line and truncates where the body header wrapped to two.
        // And Apple's HIG reserves large titles for top-level views. Both are
        // accepted for the collapse.
        //
        // The system supplies Back, so the custom back key goes; the
        // full-width back-swipe does NOT come from the chrome modifier and is
        // re-applied below (#198 drives the navigation controller directly and
        // never depended on the bar being hidden).
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Both keys bring their own raised-key chrome, so they opt OUT of
            // the toolbar's shared glass rather than nesting in a system
            // capsule — the same call the tab roots make.
            if !routine.groups.isEmpty, shareURL != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    HeaderIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Share routine", identifier: "shareRoutineButton") {
                        showingShareSheet = true
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarItem(placement: .topBarTrailing) {
                HeaderIconButton(systemImage: "slider.horizontal.3", accessibilityLabel: "Routine settings", identifier: "routineSettingsButton") {
                    showingRoutineSettings = true
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .fullWidthSwipeBack()
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
        // Adding an exercise is a SHEET now (Dave, 2026-07-25) showing the
        // Exercises catalog as its tab shows it, with the field at the bottom.
        // It replaced a pushed picker: choosing an exercise is a side errand
        // you come back from, not a place in the routine's own hierarchy — and
        // as a sheet it no longer competes with the detail's own stack.
        // PickerDestination is UUID-keyed, so no persistentModelID re-key
        // flicker while it's open.
        // ⚠️ The return runs in `onDismiss`, never under the live sheet —
        // presenting one sheet while another tears down is the documented
        // drop class on this codebase. A pick clears the target first, so
        // only a genuine cancel reopens.
        .sheet(item: $pickerDestination, onDismiss: {
            if let target = swapReturnTarget {
                swapReturnTarget = nil
                selectedExercise = target
            }
        }) { destination in
            // Labeled onSelect: the picker also has an onConfigured: param, so
            // an unlabeled trailing closure would backward-match (a deprecation
            // warning, and would misbind to onConfigured under strict
            // forward-scan). Routine building configures via its own detail
            // sheet, so it takes the plain select path.
            ExercisePickerView(
                title: destination.pickerTitle,
                onSelect: { exercise in
                    addExercise(exercise, to: destination)
                }
            )
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
        .alert(
            confirmingRailDelete.map { target in
                target.name.map { "Remove \u{201C}\($0)\u{201D}?" } ?? "Remove this exercise?"
            } ?? "",
            isPresented: Binding(
                get: { confirmingRailDelete != nil },
                set: { if !$0 { confirmingRailDelete = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let target = confirmingRailDelete {
                    deleteExercise(target.entry, in: target.group)
                }
                confirmingRailDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmingRailDelete = nil }
        } message: {
            Text("Logged history is untouched.")
        }
        .sheet(item: $selectedExercise) { ref in
            // Resolve the RoutineExercise from its stable uuid within the
            // live routine graph. Nothing to show if it was deleted.
            // ⚠️ `.sheet(item:)` presents whether or not the builder yields
            // content, so an unresolvable ref must render something with a
            // way out — an empty sheet dismissable only by drag is the
            // failure this replaces (review).
            if let routineExercise = routine.sortedGroups.flatMap(\.sortedExercises).first(where: { $0.uuid == ref.id }) {
                ExerciseDetailSheet(
                    routine: routine,
                    routineExercise: routineExercise,
                    onSwap: { entry in
                        entry.uuid.map {
                            swapReturnTarget = IdentifiedUUID(id: $0)
                            pickerDestination = .swap($0)
                        }
                    }
                )
                .presentationDetents([.large])
            } else {
                VStack(spacing: 0) {
                    SheetHeader(title: "Exercise", actionLabel: "Done", closeOnly: true) {
                        selectedExercise = nil
                    }
                    .padding(.horizontal, 18)
                    Text("This exercise is no longer in the routine.")
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 24)
                    Spacer(minLength: 0)
                }
                .presentationBackground(Theme.background)
            }
        }
        .fullScreenCover(item: $activeSession) { session in
            ActiveSessionView(session: session)
        }
        // Schedule lives in its own tray now (2026-07-22), reachable from the
        // header's tappable schedule chip AND the settings "Schedule" row.
        .sheet(isPresented: $showingScheduleTray) {
            ScheduleTray(routine: routine)
        }
        // Both pauses in one tray, because they are one question with two
        // answers and the sheet is where the difference gets explained.
        .sheet(isPresented: $showingPausesTray) {
            PausesTray(routine: routine)
        }
        // A piece the kit already has opens THAT PIECE (2026-08-01): its
        // detail screen holds membership, config and the cross-links, so the
        // chip answers about the thing tapped. (#470 presented the whole
        // catalog here — unanchored to the piece, and bare of the
        // `NavigationStack` its presented form pushes rows with, so every
        // row tap inside was a silent no-op.) The stack is load-bearing:
        // the detail screen's cross-links push within this sheet.
        .sheet(item: $kitDetailTarget) { equipment in
            NavigationStack {
                EquipmentDetailScreen(equipment: equipment)
            }
        }
        // Tapping an amber "not in your kit" gear chip opens ways to resolve it
        // (add to kit · switch kit · swap the moves). Keyed on the name.
        .sheet(item: $resolveTarget) { target in
            EquipmentResolveSheet(routine: routine, equipmentName: target.id)
        }
        // The one-time Health ask, in front of the first workout start.
        .healthStartPrimer($healthStartRequest)
        // ⚠️ REQUIRED now that the rail carries a LEADING reveal (DUPE):
        // this is a pushed screen, and the app's full-width back-swipe pan
        // begins at ~10 pt while a reveal drag needs 16, so without this
        // the pop wins every rightward drag and DUPE would be unreachable.
        // Narrowed to the 44 pt edge band on THIS screen only, and turned
        // off while routine settings is pushed on top so that screen keeps
        // its full-width pop. Same for the kit chip's equipment sheet: the
        // gate count is GLOBAL, so while it's raised the sheet's own stack
        // (cross-links push in it) would lose full-width pop too — and the
        // rail under the sheet can't take a drag anyway.
        .leadingRevealHost(active: !showingRoutineSettings && kitDetailTarget == nil)
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

    /// Material to pair (≥2 exercises) and no superset yet — the
    /// creation tip's display window.
    private var supersetTipEligible: Bool {
        !routine.sortedGroups.contains(where: \.isSuperset)
            && routine.sortedGroups.reduce(0) { $0 + $1.sortedExercises.count } >= 2
    }

    // MARK: - Header

    /// The header, the scroll's first CONTENT rather than a fixed band above
    /// it, and no longer carrying the name (the bar's large title does): the
    /// estimate column on the left, the three-row spec table on the right
    /// (`SCHEDULE` / `PAUSES` / `KIT`), a drawn gutter between. Reasoning
    /// and the full spec: docs/DECISIONS.md 2026-07-29 (+ the 2026-07-30
    /// design round: pause cells, the muscle-tag cap).
    private var header: some View {
        let meta = RoutineMeta(routine: routine, activeNames: availableEquipmentNames)
        return VStack(alignment: .leading, spacing: 0) {
            // ⚠️ NO name here (2026-07-29). It is the system navigation
            // bar's large title now, which is what collapses it into the bar
            // on scroll. Build-78 moved the name INTO the body because the
            // old centred chrome title truncated it; that reasoning is
            // reversed here in exchange for the native collapse, and the
            // cost is that a long name truncates on one line instead of
            // wrapping to two.
            //
            // ⚠️ NO notes either. They left this region entirely; the
            // settings sheet still holds the field.
            if !routine.groups.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    estimateColumn(meta)
                    columnRule
                    specTable(meta)
                }
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    /// The gutter between the two header columns, drawn (2026-07-29, Dave:
    /// the split needed "some way of making sure the two columns are clear").
    ///
    /// It is the SAME hairline the spec table already puts between its rows,
    /// turned on its side, so the three horizontal rules now start on a
    /// vertical one and the right column reads as a table rather than as text
    /// that happens to be right of other text. Nothing new is introduced: one
    /// weight, one colour, one idea.
    ///
    /// The alternative was a filled ground behind one column, and it costs
    /// more than it gives here. A panel in a cardless screen reads as a card
    /// you can open, and neither column is; the muscle tags in the left column
    /// already wear `surfaceRaised` over `background`, so putting them on
    /// `surface` would flatten the tag against its own ground — a tag stops
    /// looking like a tag.
    ///
    /// It spans the taller column: the rule IS the gutter, so it ends where
    /// the header does.
    private var columnRule: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1)
            .padding(.horizontal, 12)
            .accessibilityHidden(true)
    }

    /// The left column: what the routine COSTS, in the order you ask it.
    /// All derived, so all inert text — the estimate answers "do I have time
    /// for this", the set count is the workload you would otherwise sum down
    /// the rail, and the muscle groups say what it covers more precisely than
    /// a single focus word did.
    private func estimateColumn(_ meta: RoutineMeta) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let estimate = meta.estimate {
                Text(estimate)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(meta.workUnit.counted(meta.sets))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
            let muscles = routine.muscleGroups
            if !muscles.isEmpty {
                // Two tags + a "+N" overflow (Dave's pick, design round
                // 2026-07-30): the 104 pt column stacks tags one per line,
                // so an uncapped list made this column the header's tallest
                // element. The cap bounds the tower; assistive tech gets
                // the whole list below, so nothing is hidden from anyone
                // who can't glance.
                FlowLayout(spacing: 4) {
                    ForEach(muscles.prefix(2), id: \.self) { group in
                        CardCapsule(text: group.displayName).view()
                    }
                    if muscles.count > 2 {
                        CardCapsule(text: "+\(muscles.count - 2)").view()
                    }
                }
                .padding(.top, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(muscles.map(\.displayName).joined(separator: ", "))
            }
        }
        .frame(width: estimateColumnWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The right column. Mono caps label left, value hard right, hairline
    /// under all but the last, and every row a door.
    ///
    /// ⚠️ The KIT row takes no tap of its own — its tags are each their own
    /// target, and a row-level door plus per-tag doors would be nested tap
    /// targets. That is why it alone carries no trailing chevron.
    private func specTable(_ meta: RoutineMeta) -> some View {
        VStack(spacing: 0) {
            RoutineSpecRow(label: "schedule", action: { showingScheduleTray = true }) {
                Text(RoutineMeta.cadence(routine.schedule))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
            }
            specHairline
            // Rest and transition are one row (2026-07-29). They are the same
            // KIND of fact — how long you wait — and each number carries its
            // own noun, so position never has to be decoded. Merging them also
            // took `TRANSITION`, the longest label in the block, out of the
            // left edge every value was aligning against.
            //
            // ⚠️ Two side-by-side CELLS, noun under number (Dave's pick,
            // design round 2026-07-30). The one-line phrase wrapped
            // mid-phrase at the DEFAULT type size on a standard phone
            // ("45s between / sets") — the wrap-not-truncate rule firing
            // where it was never meant to. Stacking by design means nothing
            // ever breaks mid-phrase, and an accessibility size wraps the
            // noun within its cell instead of changing the row's shape.
            RoutineSpecRow(label: "pauses", action: { showingPausesTray = true }) {
                HStack(alignment: .top, spacing: 16) {
                    pauseCell(RoutineMeta.restLabel(routine.restSeconds), noun: "between sets")
                    pauseCell(RoutineMeta.restLabel(routine.transitionSeconds), noun: "between exercises")
                }
            }
            if !meta.gear.isEmpty {
                specHairline
                RoutineSpecRow(label: "kit", showsChevron: false) {
                    // An equipment-free routine's tag is the synthetic
                    // "Bodyweight" stand-in — not a piece of equipment, so
                    // there is nothing to open and it renders INERT (no
                    // ring, no tap). Real gear stays interactive per-piece.
                    RoutineEquipmentTags(
                        gear: meta.gear,
                        interactive: !routine.equipmentNames.isEmpty
                    ) { name in
                        if availableEquipmentNames.contains(name) {
                            kitDetailTarget = equipment(named: name)
                        } else {
                            resolveTarget = ResolveTarget(name: name)
                        }
                    }
                }
            }
        }
    }

    private var specHairline: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
    }

    /// One pause cell: the number in ink, its noun quiet beneath it. The
    /// noun is what makes the merged row readable without a legend, so it
    /// still WRAPS rather than truncating (2026-07-29) — within its cell,
    /// where a second line is the answer and "between exercis…" is not.
    private func pauseCell(_ value: String, noun: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(noun)
                .font(.system(.caption2))
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(noun)")
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

    private func railList(width: Double) -> some View {
        let ledger = ledgerByID
        let heights = railRowHeights(width: width, ledger: ledger)
        let sizes = groupSizes
        let layout = RailLayout.build(rowHeights: heights)
        let offsets = rowOffsets(heights: heights, layout: layout)
        let groups = routine.sortedGroups
        let ringGroup = activeRingGroup

        // Rows are REAL layout (a plain VStack) so the ScrollView sizes
        // and scrolls naturally — #87's below-the-fold bug came from
        // offset-positioned rows that occupied no layout space. Offsets
        // now carry only the drag-preview deltas.
        // ⚠️ The header is a SIBLING of the rows stack, never inside it
        // (2026-07-29). Every rail coordinate — the UIKit long-press
        // recogniser's y, the ring highlight, the drag preview — is measured
        // from the rows stack's own origin by `.overlay(alignment: .topLeading)`,
        // so putting the header in that same stack would shift y=0 to the
        // header's top and break every drop target by the header's height.
        // As a sibling it scrolls with the list and changes no geometry.
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                // Inline in the flow, not a popover (Dave, build-45: the
                // balloon anchored to the rail's top edge read as randomly
                // placed and floated over the first rows). An inline card
                // sits between the facts and the list it explains, and
                // displaces content instead of covering it. Still a
                // SIBLING gate — conditional content must never wrap the
                // rows stack (identity churn mid-gesture, #270).
                SupersetTipInline(
                    hasSuperset: routine.sortedGroups.contains(where: \.isSuperset)
                )

                columnHeaders

                railRows(groups: groups, ringGroup: ringGroup, offsets: offsets, layout: layout, heights: heights, sizes: sizes, ledger: ledger)
            }
        }
        .scrollDisabled(railGesture != .idle)
        .sensoryFeedback(.impact(weight: .light), trigger: gestureFeedbackToken(heights: heights))
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

    /// The rows themselves, with every gesture overlay measured from THIS
    /// stack's origin. Extracted so the header can sit above it without
    /// entering its coordinate space.
    private func railRows(
        groups: [ExerciseGroup],
        ringGroup: Int?,
        offsets: [RailRowKind: Double],
        layout: RailLayout,
        heights: [[Double]],
        sizes: [Int],
        ledger: [String: RoutineLedgerRow]
    ) -> some View {
            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.uuid) { g, group in
                    ForEach(Array(group.sortedExercises.enumerated()), id: \.element.uuid) { i, routineExercise in
                        positionedRailRow(
                            routineExercise, group: group, groupIndex: g, index: i,
                            ringGroup: ringGroup, offsets: offsets, layout: layout, sizes: sizes, ledger: ledger
                        )
                    }
                }
                addExerciseRow
            }
            .overlay(alignment: .topLeading) {
                // The long-press layer for both #78 gestures. UIKit, not
                // SwiftUI — see RailGestureRecognizer for the why. The
                // closures capture this render's `heights`; structure never
                // mutates while a gesture is live, so the captured geometry
                // stays true for the gesture's whole life.
                RailGestureRecognizer(
                    shouldReceive: { exerciseRowExists(at: $0.y, heights: heights) },
                    began: { beginRailGesture(at: $0, heights: heights) },
                    moved: { moveRailGesture(to: $0, heights: heights) },
                    ended: { location, cancelled in endRailGesture(at: location, cancelled: cancelled, heights: heights) }
                )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) { ringHighlight(layout: layout, heights: heights, sizes: sizes) }
            .overlay(alignment: .topLeading) { supersetLandingFX(layout: layout, sizes: sizes) }
            .overlay(alignment: .topLeading) { floatingDragPreview(layout: layout, groups: groups) }
            .animation(Theme.Anim.standard, value: offsets)
            .padding(.top, 10)
            // 12, not the header's 20 (Dave, design round 2026-07-30:
            // "the left rail should be further to the left") — the glyph
            // column is structure, not content, so it sits nearer the edge
            // and the name column gains the width.
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.bottom, 8)
    }

    /// The rail's column headers, held at the top of the scroll while the
    /// rows pass under them. Dave's call: ONLY these pin — the estimate and
    /// the spec table scroll away with the title, because nothing in the
    /// header is consulted mid-list and pinning it would spend list height on
    /// facts already read.
    ///
    /// ⚠️ Sticky via a pure render-time `visualEffect`, the same mechanism
    /// Today's week strip uses, and for the same reason: it reads geometry
    /// without writing state. `onScrollGeometryChange` would also work and is
    /// FORBIDDEN here — it writes during layout, which breaks the search-role
    /// morph on first activation anywhere in the TabView subtree.
    ///
    /// A sticky band floats, so it stops occluding by accident: it needs an
    /// opaque ground of its own or rows read through it, and a zIndex, since
    /// the rows are a later sibling and would otherwise draw over it.
    @ViewBuilder
    private var columnHeaders: some View {
        if !routine.groups.isEmpty {
            // ⚠️ Spacing 13, matching the gap between the two run columns in
            // the row below (device pass, 2026-07-29) — an 8 here sat the
            // TARGET label 5 pt right of the column it names, which on a
            // right-aligned mono column is plainly visible.
            HStack(spacing: 13) {
                Spacer(minLength: 0)
                columnLabel("target")
                columnLabel("prev")
            }
            .padding(.top, 10)
            .padding(.bottom, 6)
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .background(Theme.background)
            // The shelf's drawn edge (Dave's pick, design round 2026-07-30):
            // rows sliding under the pinned band used to clip against an
            // INVISIBLE line — a name vanishing mid-letter into empty air.
            // The same hairline the spec table and the header gutter already
            // use, its third job; full-bleed so the edge is the band's, not
            // the labels'.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
            }
            .visualEffect { content, proxy in
                content.offset(y: max(0, -proxy.frame(in: .scrollView).minY))
            }
            .zIndex(1)
            .accessibilityHidden(true)
        }
    }

    private func columnLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Theme.textFaint)
            .frame(width: runColumnWidth, alignment: .trailing)
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
            .frame(width: 28, height: addRowHeight)

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
        .frame(height: addRowHeight)
    }

    /// One row: swipe-revealable content with the two long-press zones —
    /// the rail column grabs the ring, the body drags the row.
    /// One positioned rail row, extracted WHOLE so the doubly-nested
    /// ForEach body is a single typed call — the inline chain sat at the
    /// type-checker's time budget and the first-row tip anchor pushed it
    /// over (CI-caught, twice: first as let+if/else, then as a bare
    /// added modifier). The tip pins to the first row per Dave
    /// (2026-07-23); see FirstRowSupersetTipAnchor.
    private func positionedRailRow(
        _ routineExercise: RoutineExercise,
        group: ExerciseGroup,
        groupIndex g: Int,
        index i: Int,
        ringGroup: Int?,
        offsets: [RailRowKind: Double],
        layout: RailLayout,
        sizes: [Int],
        ledger: [String: RoutineLedgerRow]
    ) -> some View {
        railRow(
            routineExercise, group: group, groupIndex: g, index: i,
            // The row's own computed height, read back from the same layout
            // the gestures use — one geometry, two readers.
            height: layout.row(for: .exercise(group: g, index: i))?.height ?? railRowMinHeight,
            hideLoop: ringGroup == g,
            landing: landingParams(groupIndex: g, index: i, layout: layout, sizes: sizes),
            ledger: ledger
        )
        .offset(y: offsets[.exercise(group: g, index: i)] ?? 0)
        .modifier(FirstRowSupersetTipAnchor(isFirst: g == 0 && i == 0))
    }

    private func railRow(_ routineExercise: RoutineExercise, group: ExerciseGroup, groupIndex g: Int, index i: Int, height: Double, hideLoop: Bool, landing: RailLandingParams, ledger: [String: RoutineLedgerRow]) -> some View {
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
            // The drag equivalent (ring-into-ring merge) has no gesture-free
            // path otherwise (#164 parity): offer it when the neighbour in
            // that direction is also a superset. This row's group survives.
            let allGroups = routine.sortedGroups
            if g > 0, allGroups[g - 1].isSuperset {
                let above = allGroups[g - 1]
                a11yActions.append(SwipeRowAction(name: "Merge with superset above") {
                    openSwipeRow = nil
                    routine.mergeGroup(above, direction: 1, context: modelContext)
                })
            }
            if g < lastGroup, allGroups[g + 1].isSuperset {
                let below = allGroups[g + 1]
                a11yActions.append(SwipeRowAction(name: "Merge with superset below") {
                    openSwipeRow = nil
                    routine.mergeGroup(below, direction: -1, context: modelContext)
                })
            }
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
            duplicateExercise(routineExercise)
        })
        a11yActions.append(SwipeRowAction(name: "Delete") {
            openSwipeRow = nil
            confirmingRailDelete = RailDeleteTarget(
                name: routineExercise.exercise?.name,
                entry: routineExercise,
                group: group
            )
        })

        // Activation is the component's onTap (see the SwipeRevealRow
        // contract): the old row-body and dot-zone onTapGestures were
        // the same latent bug class as the list rows' Buttons — a tap
        // gesture INSIDE content can fire on a reveal drag's release.
        // One component tap now covers the whole row including the dot
        // zone (whose ring gesture stays in the UIKit long-press layer);
        // `enabled: railGesture == .idle` keeps a second finger from
        // opening sheets or closing rows while a rail gesture is live.
        // ⚠️ The two acts sit on the edges the app's swipe law assigns
        // them (2026-07-28): LEADING is curation, so DUPE reveals under a
        // rightward drag; TRAILING is destructive, so DELETE keeps the
        // left. They shared the trailing edge until now, which put a
        // duplicate one thumb-width from a delete on the edge that means
        // "destroy" everywhere else in the app. Each block is one 58 pt
        // `SwipeActionButton`.
        return SwipeRevealRow(
            id: routineExercise.persistentModelID,
            openRow: $openSwipeRow,
            enabled: railGesture == .idle,
            actionsWidth: 58,
            leadingActionsWidth: 58,
            onTap: { selectedExercise = routineExercise.uuid.map(IdentifiedUUID.init) },
            accessibilityActions: a11yActions
        ) {
            ExerciseRailRow(
                routineExercise: routineExercise,
                role: railRole(index: i, of: group),
                ledger: routineExercise.uuid.map { ledger[$0.uuidString] } ?? nil,
                rowHeight: height,
                runColumnWidth: runColumnWidth,
                textTopInset: railTextTopInset,
                nodeY: Double(railNodeY),
                hideLoop: hideLoop,
                landing: landing
            )
            .contentShape(Rectangle())
        } actions: {
            SwipeActionButton(label: "DELETE", color: Theme.swipeDelete) {
                openSwipeRow = nil
                deleteExercise(routineExercise, in: group)
            }
        } leadingActions: {
            SwipeActionButton(label: "DUPE", color: Theme.primaryFill, labelColor: Theme.onPrimary) {
                openSwipeRow = nil
                duplicateExercise(routineExercise)
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
    private func exerciseRowExists(at y: Double, heights: [[Double]]) -> Bool {
        let layout = RailLayout.build(rowHeights: heights)
        guard let last = layout.rows.last, y >= 0, y < last.maxY else { return false }
        return layout.exercise(at: y) != nil
    }

    private func beginRailGesture(at location: CGPoint, heights: [[Double]]) {
        let x = Double(location.x)
        let y = Double(location.y)
        guard railGesture == .idle else { return }
        // A press with a swipe open just closes the swipe.
        guard openSwipeRow == nil else {
            openSwipeRow = nil
            return
        }
        let layout = RailLayout.build(rowHeights: heights)
        // Same bound as shouldReceive: never grab from outside a row.
        guard let last = layout.rows.last, y >= 0, y < last.maxY,
              let (g, i) = layout.exercise(at: y) else { return }

        if x < Self.dotZoneWidth {
            // Every ring press waits for the first movement to pick its edge
            // from the drag DIRECTION (not the nearest edge): dragging down
            // works the bottom, up works the top, from ANY pressed row. That
            // is what lets a press anywhere in the list gather everything
            // from here to the top/bottom into one superset.
            railGesture = .ring(group: g, edge: nil, pressY: y, fingerY: y)
        } else {
            let rowY = layout.row(for: .exercise(group: g, index: i))?.y ?? 0
            railGesture = .dragging(group: g, index: i, fingerY: y, grabOffset: y - rowY)
        }
    }

    private func moveRailGesture(to location: CGPoint, heights: [[Double]]) {
        let y = Double(location.y)
        switch railGesture {
        case .idle:
            break
        case .dragging(let g, let i, _, let grabOffset):
            railGesture = .dragging(group: g, index: i, fingerY: y, grabOffset: grabOffset)
        case .ring(let g, let heldEdge, let pressY, _):
            var edge = heldEdge
            if edge == nil, abs(y - pressY) > 10 {
                // Latch the EJECT edge from the pressed member (not the drag
                // direction): the unite direction comes from the finger's
                // position in `span`, so this only decides which end an
                // inward drag trims. Deferred to first movement so the
                // pre-move highlight still reads as the whole pressed group.
                let layout = RailLayout.build(rowHeights: heights)
                let pressedIndex = layout.exercise(at: pressY).map { $0.group == g ? $0.index : 0 } ?? 0
                edge = RailRing.grabbedEdge(groupSizes: groupSizes, group: g, pressedIndex: pressedIndex)
            }
            railGesture = .ring(group: g, edge: edge, pressY: pressY, fingerY: y)
        }
    }

    private func endRailGesture(at location: CGPoint, cancelled: Bool, heights: [[Double]]) {
        let y = Double(location.y)
        defer { railGesture = .idle }
        guard !cancelled else { return }
        switch railGesture {
        case .idle:
            break
        case .dragging(let g, let i, _, let grabOffset):
            commitDrag(group: g, index: i, fingerY: y, grabOffset: grabOffset, heights: heights)
        case .ring(let g, let edge, _, _):
            if let edge { commitRing(group: g, edge: edge, fingerY: y, heights: heights) }
        }
    }

    /// The dragged row's tentative drop target, from the floating row's
    /// visual center — the dragged row's OWN height, since rows differ now.
    private func tentativeTarget(heights: [[Double]]) -> RailDropTarget? {
        guard case .dragging(let g, let i, let fingerY, let grabOffset) = railGesture else { return nil }
        let draggedHeight = heights.indices.contains(g) && heights[g].indices.contains(i)
            ? heights[g][i] : railRowMinHeight
        let centerY = fingerY - grabOffset + draggedHeight / 2
        return RailDrag.nearestTarget(rowHeights: heights, dragging: (group: g, index: i), fingerY: centerY)
    }

    /// Per-row deltas from the natural layout. Empty when idle; during a
    /// drag every surviving row shifts by (previewY − idleY) and the
    /// dragged row gets no entry — it stays anchored (hidden) in place,
    /// so nothing ever flies to the top of the viewport (#87).
    private func rowOffsets(heights: [[Double]], layout: RailLayout) -> [RailRowKind: Double] {
        guard case .dragging(let g, let i, _, _) = railGesture,
              let target = tentativeTarget(heights: heights) else { return [:] }
        let preview = RailDrag.previewPositions(rowHeights: heights, dragging: (group: g, index: i), target: target)
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
    private func gestureFeedbackToken(heights: [[Double]]) -> Int {
        switch railGesture {
        case .idle:
            return 0
        case .dragging:
            return tentativeTarget(heights: heights)?.hashValue ?? 0
        case .ring(let g, let edge, _, let fingerY):
            guard let edge else { return 1 }
            let span = RailRing.span(rowHeights: heights, group: g, edge: edge, fingerY: fingerY)
            return span.firstFlat &* 31 &+ span.lastFlat
        }
    }

    @ViewBuilder
    private func ringHighlight(layout: RailLayout, heights: [[Double]], sizes: [Int]) -> some View {
        if case .ring(let g, let edge, _, let fingerY) = railGesture, sizes.indices.contains(g) {
            // Before a direction is chosen (solo press, finger still) the
            // highlight spans the pressed group; after, the live span.
            let span: RingSpan? = edge.map { RailRing.span(rowHeights: heights, group: g, edge: $0, fingerY: fingerY) }
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
        return RailLandingParams(
            active: true,
            progress: landing.progress,
            grew: landing.grew,
            firstNodeY: firstRow.y + railNodeY,
            lastNodeY: lastRow.y + railNodeY,
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
            let firstNodeY = firstRow.y + railNodeY
            let lastNodeY = lastRow.y + railNodeY
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
            // The lifted card is the row it lifted: same (computed) height,
            // so its spine spans the card instead of stopping short inside it.
            let liftedHeight = layout.row(for: .exercise(group: g, index: i))?.height ?? railRowMinHeight
            ExerciseRailRow(
                routineExercise: routineExercise,
                role: .solo,
                rowHeight: liftedHeight,
                runColumnWidth: runColumnWidth,
                textTopInset: railTextTopInset,
                nodeY: Double(railNodeY)
            )
                .padding(.horizontal, 8)
                .frame(height: liftedHeight)
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

    private func commitDrag(group g: Int, index i: Int, fingerY: Double, grabOffset: Double, heights: [[Double]]) {
        let sizes = groupSizes
        guard sizes.indices.contains(g), i < sizes[g] else { return }
        let draggedHeight = heights.indices.contains(g) && heights[g].indices.contains(i)
            ? heights[g][i] : railRowMinHeight
        let centerY = fingerY - grabOffset + draggedHeight / 2
        guard let target = RailDrag.nearestTarget(rowHeights: heights, dragging: (group: g, index: i), fingerY: centerY) else { return }

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

    private func commitRing(group g: Int, edge: RingEdge, fingerY: Double, heights: [[Double]]) {
        let sizes = groupSizes
        guard sizes.indices.contains(g) else { return }
        let span = RailRing.span(rowHeights: heights, group: g, edge: edge, fingerY: fingerY)
        guard !span.isNoOp else { return }
        let group = routine.sortedGroups[g]

        // Captured BEFORE the merges: did this landing grow an existing
        // superset, or form a fresh one? Drives whether the loop is kept
        // through the reshape or revealed.
        let wasExistingSuperset = group.sortedExercises.count > 1

        // Unite: pull each whole group above/below (solo OR superset) into
        // the pressed group, which survives and keeps its block config. One
        // merge per spanned group; re-reading the index each pass follows
        // the shift as neighbours collapse in.
        for _ in 0..<span.absorbAfter {
            let groups = routine.sortedGroups
            guard let index = groups.firstIndex(where: { $0 === group }),
                  groups.indices.contains(index + 1) else { break }
            routine.mergeGroup(groups[index + 1], direction: -1, context: modelContext)
        }
        for _ in 0..<span.absorbBefore {
            let groups = routine.sortedGroups
            guard let index = groups.firstIndex(where: { $0 === group }),
                  index > 0 else { break }
            routine.mergeGroup(groups[index - 1], direction: 1, context: modelContext)
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
        case .swap(let uuid):
            // ⚠️ Cleared BEFORE the guard, not after (review): a pick is not
            // a cancel whether or not the slot still resolves, and leaving
            // the target set here reopened a sheet for a slot that no longer
            // exists — which presents EMPTY, because `.sheet(item:)` presents
            // whether or not its builder produces content.
            swapReturnTarget = nil
            // Resolve the slot within the live graph; a slot deleted while
            // the picker was up (another device, an Operator apply) is a
            // clean no-op, not a crash.
            guard let entry = routine.sortedGroups.flatMap(\.sortedExercises).first(where: { $0.uuid == uuid }) else { return }
            // Targets reset to the new exercise's add-time defaults by the
            // model (the equipment-resolve law: a barbell weight must not
            // linger on a bodyweight sub). Sets/rest are group facts and
            // stay.
            routine.replaceExercise(entry, with: exercise)
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

    /// The design's DUPE. The mutation itself is `Routine.duplicateExercise`
    /// (#508, b19) — this is the interactive door, which owns the save.
    private func duplicateExercise(_ routineExercise: RoutineExercise) {
        routine.duplicateExercise(routineExercise, context: modelContext)
        // Permanent id before the duplicated row can be tapped open — an
        // item-keyed tray re-keys and flickers if the id swaps under it on
        // a later autosave (see addExercise for the full mechanism).
        try? modelContext.save()
    }

}

/// One row of routine detail's spec table: a mono caps label on the left, the
/// value hard right, an optional trailing chevron. The whole row is the tap
/// target when it has one.
///
/// Lives here rather than in `Views/Components/` because exactly one screen
/// builds this table. It moves the day a second one does — no earlier.
private struct RoutineSpecRow<Value: View>: View {
    let label: String
    var showsChevron = true
    var action: (() -> Void)?
    @ViewBuilder let value: () -> Value

    /// Wide enough for the longest label in the table (`SCHEDULE`) at the
    /// default size, so the values start on one x without anything being
    /// pushed to the far edge to get there.
    @ScaledMetric(relativeTo: .caption2) private var labelWidth: Double = 62

    var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // ⚠️ The label is a fixed COLUMN and the value sits right next to
            // it (device pass, 2026-07-29). The first cut gave the label
            // `.frame(maxWidth: .infinity)`, which did two things at once:
            // it drove every value to the far right edge, opening ~90 pt of
            // dead space between a label and the value it names (the exact
            // horizontal eye travel this arrangement exists to avoid), and it
            // left the value whatever width was over — so "45s between sets"
            // ellipsized to "45s between…" and the kit tags stacked one per
            // line. The nouns and the tag names ARE this table's
            // disambiguation; they get the room, and the slack goes at the
            // trailing edge where the chevron is.
            Text(label.uppercased())
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Theme.textFaint)
                .fixedSize()
                .frame(minWidth: labelWidth, alignment: .leading)
            // ⚠️ The value takes the whole remainder and aligns LEADING —
            // never a trailing `Spacer` beside it. `FlowLayout.sizeThatFits`
            // returns `proposal.width ?? 0`, so it reads to an `HStack` as
            // infinitely flexible; a `Spacer` is too, and the stack splits the
            // remainder EVENLY between two equally flexible children. That
            // handed the kit tags half the room they had, which is the second
            // way to make them stack one per line.
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// Rest and transition in one tray (2026-07-29), because the header now shows
/// them as one row. The explainer is the whole reason the merge is safe: two
/// numbers under one label need somewhere that says which is which, and this
/// is it.
private struct PausesTray: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var routine: Routine

    @State private var showingRestScrubber = false
    @State private var showingTransitionScrubber = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ⚠️ `SheetHeader` carries NO horizontal padding of its own — the
            // tray supplies it, at 18, because the scrolling content below has
            // to be full-bleed so rows clip at the sheet's edges rather than
            // at a padded inset. Every other tray in the app does this; this
            // one shipped without it (2026-07-29), which put the title flush
            // against the sheet's left edge and ran "Done" off the right.
            SheetHeader(title: "Pauses", closeOnly: true) { dismiss() }
                .padding(.horizontal, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
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

                    MetricStepperRow(
                        label: "Transition",
                        value: WorkoutMetric.transition.displayText(Double(routine.transitionSeconds)),
                        identifier: "transition",
                        onTapValue: { showingTransitionScrubber = true },
                        onDecrement: { routine.transitionSeconds = Int(WorkoutMetric.transition.decremented(Double(routine.transitionSeconds))) },
                        onIncrement: { routine.transitionSeconds = Int(WorkoutMetric.transition.incremented(Double(routine.transitionSeconds))) }
                    )
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))

                    Text("Rest is the wait between sets of the same exercise. Transition is the shorter wait when you move to a different one, or to a superset partner. Set 0 to skip a countdown.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                }
                // 18, matching the header above and every sibling tray.
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.background)
        .presentationDetents([.medium])
        .sheet(isPresented: $showingRestScrubber) {
            MetricWheelSheet(
                metric: .rest,
                value: Binding(
                    get: { Double(routine.restSeconds) },
                    set: { routine.restSeconds = Int(($0 ?? Double(routine.restSeconds)).rounded()) }
                )
            )
        }
        .sheet(isPresented: $showingTransitionScrubber) {
            MetricWheelSheet(
                metric: .transition,
                value: Binding(
                    get: { Double(routine.transitionSeconds) },
                    set: { routine.transitionSeconds = Int(($0 ?? Double(routine.transitionSeconds)).rounded()) }
                )
            )
        }
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
/// Pins the superset creation tip's popover to the FIRST rail row
/// (Dave, 2026-07-23): a popover on a real exercise, not the build-45
/// balloon floating at the rail's top edge. The branch depends only on
/// POSITION, so superset formation never re-identifies a row
/// mid-landing (#270); display is gated in the tip's own canPair rule.
private struct FirstRowSupersetTipAnchor: ViewModifier {
    let isFirst: Bool

    func body(content: Content) -> some View {
        if isFirst {
            content.popoverTip(SupersetCreationTip(), arrowEdge: .top)
        } else {
            content
        }
    }
}

private struct SupersetTipInline: View {
    let hasSuperset: Bool

    var body: some View {
        // Loop tip only, since 2026-07-23: the creation tip moved to a
        // popover pinned on the first rail row (teaching the gesture).
        // This inline card still introduces a loop the user didn't draw
        // (an instantiated template, a shared import).
        if hasSuperset {
            TipView(SupersetLoopTip())
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
        }
    }
}

/// Where a picked exercise should land: a fresh group at the end, or an
/// existing group (forming a superset).
/// What a VoiceOver "Delete" is asking about (#508, Q22-B + review). Holds
/// the models directly rather than a uuid: the alert is raised and answered
/// within one screen's lifetime, and re-resolving would only reintroduce the
/// unresolvable-ref case the sheet builder now guards against.
struct RailDeleteTarget: Identifiable {
    let name: String?
    let entry: RoutineExercise
    let group: ExerciseGroup
    var id: ObjectIdentifier { ObjectIdentifier(entry) }
}

enum PickerDestination: Identifiable, Hashable {
    case newGroup
    /// A swap target (round 2a): the RoutineExercise slot whose exercise
    /// the pick replaces, keyed on its stable `uuid` (not its
    /// persistentModelID, which would re-key the open picker on
    /// autosave). A `.group(UUID)` superset-target case died with round
    /// 2a — its only producer, the sheet's `onAddToSuperset`, was never
    /// called from anywhere (swift-reviewer archaeology; joining a
    /// superset is the rail's ring drag and the sheet's merge keys).
    case swap(UUID)

    var id: AnyHashable {
        switch self {
        case .newGroup: AnyHashable("newGroup")
        case .swap(let uuid): AnyHashable("swap-\(uuid.uuidString)")
        }
    }

    /// What the picker sheet calls itself — the same list doing two jobs.
    var pickerTitle: String {
        switch self {
        case .newGroup: "Add exercise"
        case .swap: "Swap exercise"
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
    let routineExercise: RoutineExercise
    let role: RailRole
    /// This exercise's target-vs-prev, from the shared `RoutineLedger`.
    /// Nil while the rows are being dragged into a preview, where the
    /// numbers are not what the gesture is about.
    var ledger: RoutineLedgerRow?
    var rowHeight: Double = 52
    /// Sized for reps over weight on two lines; a single-line cell needs
    /// ~90 pt and starves the name column beside the 28 pt rail. The
    /// SCREEN's scaled value, passed in — the height computation and the
    /// pinned headings read the same number (2026-07-30).
    var runColumnWidth: Double = 58
    /// How far the row's text sits below its top edge, and the node's centre
    /// measured from the same edge. Both are the SCREEN's, passed in, because
    /// the superset landing FX place their band and spark against these same
    /// nodes — see `RoutineDetailView.railNodeY`.
    ///
    /// The node lands on the name's first line only because the content is
    /// TOP-aligned and carries `textTopInset` itself — see `body`.
    var textTopInset: Double = 9
    var nodeY: Double = 20
    /// Ring-edit mode (#87): the small loop and the expanded full-width
    /// ring are mutually exclusive — the active group's rows drop their
    /// loop drawing while the highlight is up.
    var hideLoop = false
    /// The create → static landing for this row's group, forwarded to the
    /// glyph. Inert (`isLanding == false`) at rest.
    var landing = RailLandingParams()

    /// One mono column, right-aligned, printing the prescription over at most
    /// two lines: what is being done above what it is loaded with.
    ///
    /// ⚠️ `PrescriptionRun`s are FRAGMENTS of one line ("3", "×", "10–15",
    /// " @ ", "35lb"), not lines — so each printed line composes its fragments
    /// into a single concatenated `Text` exactly as `DiffLedger` composes
    /// them, with the ink applied per fragment. Rendering one run per line
    /// would break "3×10" into three rows.
    ///
    /// ⚠️ And the break is CHOSEN, never left to word wrap (device pass,
    /// 2026-07-29). Wrapping put the break wherever the glyphs happened to
    /// run out: "3×8 @" / "10 lb" stranded the separator at the end of a line,
    /// and the two columns broke at different points on the same row
    /// ("3×9–14" / "@ 35 lb" beside "3×10 @" / "35 lb"), so the pair could not
    /// be read across. Splitting at the load separator — and dropping it, the
    /// line break now says what it said — makes both columns break at the same
    /// place on every row.
    private func runColumn(_ runs: [PrescriptionRun], changed: Set<RoutineDiff.Field>, directions: [RoutineDiff.Field: RoutineDiff.Direction], lit: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            if runs.isEmpty {
                // A bare dash for every empty cell, "new" included (Dave's
                // pick, design round 2026-07-30) — the placeholder glyph,
                // not a word doing a caption's job.
                Text("—").foregroundStyle(Theme.textFaint)
            } else {
                let lines = Self.printedLines(runs)
                ForEach(lines.indices, id: \.self) { index in
                    lines[index].reduce(Text("")) { result, run in
                        result + Text(run.text).foregroundStyle(ink(run, changed: changed, directions: directions, lit: lit))
                    }
                    .lineLimit(1)
                    // The one shape that overruns 58 pt is a cardio block with
                    // no load to break at ("5× 1000 m"). It shrinks a hair
                    // rather than wrapping into a shape nothing else has.
                    .minimumScaleFactor(0.75)
                }
            }
        }
        .font(.system(.caption, design: .monospaced))
        .frame(width: runColumnWidth, alignment: .trailing)
    }

    /// The fragments split into the lines the cell prints, at the load
    /// separator (" @ "), which the break replaces. Everything else is one
    /// line — a cardio block's "4× 500 m" has nothing to separate.
    /// Static so the screen's row-height computation counts the same lines
    /// this cell prints.
    static func printedLines(_ runs: [PrescriptionRun]) -> [[PrescriptionRun]] {
        guard let split = runs.firstIndex(where: { $0.field == nil && $0.text.contains("@") }) else {
            return [runs]
        }
        return [Array(runs[..<split]), Array(runs[(split + 1)...])]
    }

    /// The target column dims what held and marks what moved — with
    /// DIRECTION since 2026-07-30: an ask above the printed prev in the
    /// data green, below it in the gentle brick (Dave: "decrease is not a
    /// problem"). A changed neutral setting stays plain bright. Prev is one
    /// flat brightness throughout, because it is the thing being compared
    /// against rather than the thing being read. A separator fragment
    /// belongs to no field and is never emphasized.
    ///
    /// ⚠️ Kept in step with `DiffLedger.ink` by hand — the two surfaces
    /// print the same producer's rows and must agree on what a moved token
    /// wears.
    private func ink(_ run: PrescriptionRun, changed: Set<RoutineDiff.Field>, directions: [RoutineDiff.Field: RoutineDiff.Direction], lit: Bool) -> Color {
        guard lit else { return Theme.textSecondary }
        guard let field = run.field, changed.contains(field) else { return Theme.textFaint }
        return switch directions[field] {
        case .up: Theme.increaseInk
        case .down: Theme.decreaseInk
        case nil: Theme.textPrimary
        }
    }

    var body: some View {
        // ⚠️ TOP-aligned, and the text carries its own inset (device pass,
        // 2026-07-29). This was a plain `HStack`, which vertically CENTRES —
        // so the glyph, at the full 76 pt row height, kept its top edge while
        // the name floated to the middle of whatever height it had. The node
        // was drawn at a fixed y from the glyph's top and the name was not,
        // so they only ever agreed by accident, and disagreed by a different
        // amount for a one-line name than a two-line one. Top-aligning both
        // is what makes `nodeY` mean the same thing to each.
        HStack(alignment: .top, spacing: 13) {
            RailGlyph(
                role: hideLoop ? .solo : role,
                height: rowHeight,
                // ⚠️ The node centres on the first LINE of the name, not
                // on the row (2026-07-29). With names wrapping to two
                // lines a mid-row dot lands in the gap between them.
                dotY: nodeY,
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

            // The text of the row shares ONE baseline, so the ledger's first
            // line sits on the name's first line — the same line the node is
            // on — however many lines either of them runs to.
            HStack(alignment: .firstTextBaseline, spacing: 13) {
                Text(routineExercise.exercise?.name ?? "Unknown")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    // Two lines (2026-07-29). The name IS the row's content
                    // here, not a label on a card you are about to open, so it
                    // wraps where a catalog row's would.
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // The clock marks time-driven blocks (a plank, a 20:00
                // piece) — distance/calorie work speaks its unit already.
                if routineExercise.exercise?.metricProfile.contains(.duration) == true,
                   !(routineExercise.exercise?.metricProfile.tracksReps ?? false) {
                    Image(systemName: "clock")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                }

                // Today's ledger grammar, on the rail (2026-07-29): what is
                // being asked for beside what happened last time, and NO
                // delta. The target column dims what held and lights what
                // moved; prev is one flat brightness throughout, because it is
                // the thing being compared against rather than the thing being
                // read.
                //
                // ⚠️ Two lines per cell. A single-line cell needs ~90 pt,
                // which starves the name column; reps over load fits in 58.
                runColumn(ledger?.target ?? [], changed: ledger?.changed ?? [], directions: ledger?.directions ?? [:], lit: true)
                runColumn(ledger?.prev ?? [], changed: [], directions: [:], lit: false)
            }
            .padding(.top, textTopInset)
        }
        .frame(minHeight: rowHeight, alignment: .top)
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

    @State private var showingScheduleTray = false
    @State private var confirmingDelete = false
    @State private var showingRestScrubber = false
    @State private var showingTransitionScrubber = false
    /// Inline drafts (#207 — the rename/notes trays died). Name commits
    /// through Save/submit so #189's duplicate guard can veto; notes
    /// write live like every other field on this autosaving page.
    @State private var nameDraft: String
    @State private var notesDraft: String
    /// Which field holds the keyboard. Every way out clears it: a scroll, a
    /// tap on the page's ground, anything that opens a tray, a wheel or the
    /// delete alert over the page, and leaving. Return is the NAME field's
    /// exit only — in notes it types a newline.
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, notes
    }

    init(routine: Routine, onDelete: @escaping () -> Void) {
        self.routine = routine
        self.onDelete = onDelete
        _nameDraft = State(initialValue: routine.name)
        _notesDraft = State(initialValue: routine.notes ?? "")
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
                        .focused($focusedField, equals: .name)
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

                    // Schedule lives in its own tray now (2026-07-22),
                    // primarily reached from the header's schedule chip. This
                    // row is the second door for anyone who looks in settings.
                    Button {
                        // Nothing opens over this page under a standing
                        // keyboard — the tray, both wheels and the delete
                        // alert all put it away first.
                        focusedField = nil
                        showingScheduleTray = true
                    } label: {
                        HStack(spacing: 10) {
                            Text("Schedule")
                                .font(.system(.footnote, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 8)
                            Text(scheduleRowLabel)
                                .font(.system(.footnote))
                                .foregroundStyle(Theme.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(Theme.textFaint)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("scheduleRow")
                    .padding(.top, 8)
                    .sheet(isPresented: $showingScheduleTray) {
                        ScheduleTray(routine: routine)
                    }

                    SheetSectionLabel("BETWEEN SETS")
                        .padding(.top, 24)

                    MetricStepperRow(
                        label: "Rest",
                        value: WorkoutMetric.rest.displayText(Double(routine.restSeconds)),
                        identifier: "rest",
                        onTapValue: {
                            focusedField = nil
                            showingRestScrubber = true
                        },
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
                        onTapValue: {
                            focusedField = nil
                            showingTransitionScrubber = true
                        },
                        onDecrement: { routine.transitionSeconds = Int(WorkoutMetric.transition.decremented(Double(routine.transitionSeconds))) },
                        onIncrement: { routine.transitionSeconds = Int(WorkoutMetric.transition.incremented(Double(routine.transitionSeconds))) }
                    )
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                    .sheet(isPresented: $showingTransitionScrubber) {
                        // A time span like rest, so it picks on the tape
                        // (#373 landed the metric mid-flight; isTimeSpan's
                        // exhaustive switch is what caught the join).
                        MetricWheelSheet(
                            metric: .transition,
                            value: Binding(
                                get: { Double(routine.transitionSeconds) },
                                set: { routine.transitionSeconds = Int(($0 ?? Double(routine.transitionSeconds)).rounded()) }
                            )
                        )
                    }

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
                        .focused($focusedField, equals: .notes)
                        // ⚠️ The page's `.immediately` is an ENVIRONMENT value
                        // and reaches every scrollable thing under it — this
                        // field included, once notes outgrow eight lines and
                        // it scrolls internally. Without this, dragging inside
                        // the field to reach line 12 drops the keyboard
                        // mid-edit. Innermost wins, so the page keeps its
                        // setting and the field opts out (swift-reviewer;
                        // Apple documents the same carve-out for TextEditor).
                        .scrollDismissesKeyboard(.never)
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
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .keyboardGround(clearing: $focusedField)
            }
            // Same law the exercise editor learned (#489): a plain ScrollView
            // does NOT dismiss the keyboard on scroll, so a page holding
            // fields has to say so. This one has two, and the notes field
            // grows to eight lines under a keyboard covering half the page.
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Theme.background)
        // A static "Routine settings" heading (Dave, build-78): the
        // routine's name was redundant with the editable NAME field right
        // below, and truncated when long. No Save (#219): every field
        // commits live and the name commits on any exit, so the page is
        // simply always saved. Delete nests behind "…" — present, not
        // primary.
        .pushedScreenChrome(
            title: "Routine settings",
            onBack: { focusedField = nil; commitName(); dismiss() }
        ) {
            HeaderMenuKey(systemImage: "ellipsis", accessibilityLabel: "Routine options", identifier: "routineSettingsMenu") {
                Button("Delete routine", role: .destructive) {
                    focusedField = nil
                    confirmingDelete = true
                }
            }
        }
        // The full-width swipe-back pops in UIKit and never reaches
        // onBack — without this, a swipe exit silently dropped an
        // uncommitted rename. Idempotent; guarded so the delete path
        // can't race a write onto a deleted model.
        .onDisappear {
            // Also the swipe-back's only chance to drop focus — that pop
            // never reaches onBack either (SearchFieldBody's idiom, #213).
            focusedField = nil
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

    /// The current schedule, shown on the settings row that opens the tray.
    private var scheduleRowLabel: String {
        routine.schedule.normalized == .unscheduled ? "Unscheduled" : routine.schedule.shortLabel
    }

}

