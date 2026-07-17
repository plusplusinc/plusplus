import SwiftUI
import SwiftData
import PlusPlusKit

/// The Routines tab, v3 (#109): routine cards with equipment pills and
/// a contextual header + (new routine). Library/History/Settings left
/// this header with the nav restructure — Exercises and Equipment are
/// tabs, history lives on Today, settings opens from Today's header.
struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt, order: .reverse)])
    private var routines: [Routine]

    @State private var path = NavigationPath()
    @State private var openSwipeRow: SwipeRevealOpen<PersistentIdentifier>?
    /// The routine just added from a template — scrolled into view and
    /// given an entrance flash when we land back on the library, then
    /// released (Dave, 2026-07-15). Permanent id (set post-save), so it is
    /// safe as list/scroll identity.
    @State private var newlyAdded: PersistentIdentifier?
    /// Held false for one beat after an add so the new card is ABSENT from
    /// the list, then flipped true inside `withAnimation` so it fades in and
    /// the cards below slide down to make room (Dave, 2026-07-16). Reset to
    /// false where the add lands, before the list re-renders.
    @State private var revealNewCard = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header

                ScrollViewReader { proxy in
                    List {
                    ForEach(displayedRoutines) { routine in
                        SwipeRevealRow(
                            id: routine.persistentModelID,
                            openRow: $openSwipeRow,
                            actionsWidth: 58,
                            onTap: { routine.uuid.map { path.append(RoutineRef(uuid: $0)) } },
                            accessibilityActions: [
                                SwipeRowAction(name: "Delete") {
                                    openSwipeRow = nil
                                    deleteRoutine(routine)
                                }
                            ]
                        ) {
                            RoutineCard(routine: routine, justAdded: routine.persistentModelID == newlyAdded)
                        } actions: {
                            SwipeActionButton(label: "DELETE", color: Theme.destructive) {
                                openSwipeRow = nil
                                deleteRoutine(routine)
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .transition(.opacity)
                    }
                        .onMove(perform: moveRoutines)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    // A template add pops back here and sets newlyAdded;
                    // let the pop settle, then scroll the new card into
                    // view (it lands at order 0 = top, but the list may
                    // have been scrolled) and release so the entrance
                    // flash can retrigger on the next add. Lifecycle-bound
                    // via .task(id:): leaving the tab or a rapid second add
                    // cancels this in flight, and the throwing sleeps bail
                    // in the catch WITHOUT clearing newlyAdded — so a
                    // superseding add keeps its own highlight (the repo's
                    // cancel-deferred-UI-on-disappear law, ui-interaction.md).
                    .task(id: newlyAdded) {
                        guard let id = newlyAdded else { return }
                        do {
                            // Beat of absence: the card is held out of the
                            // list (revealNewCard == false) so the eye sees
                            // the row OPEN, not one that was already sitting
                            // there.
                            try await Task.sleep(for: .milliseconds(300))
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                                revealNewCard = true      // fade in + push the rest down
                            }
                            // Let the fade begin, then bring the card into view.
                            try await Task.sleep(for: .milliseconds(60))
                            withAnimation(Theme.Anim.standard) {
                                proxy.scrollTo(id, anchor: .top)
                            }
                            try await Task.sleep(for: .milliseconds(1600))
                        } catch {
                            // Cancelled (tab left, or a superseding add whose
                            // callback already reset the flags): leave state
                            // alone so the newer add keeps its own entrance.
                            return
                        }
                        newlyAdded = nil
                    }
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            // A plain push, no hero zoom (Dave, build 37): the #216 zoom
            // made list -> detail read as a custom cover rather than a
            // navigation push. Today's zooms (committed card -> record,
            // pending card -> workout cover) are unchanged.
            .navigationDestination(for: RoutineRef.self) { ref in
                // Resolve the routine from its stable uuid (not by pushing
                // the @Model, whose persistentModelID can swap under the
                // push). A just-created routine resolves via a direct fetch.
                if let routine = modelContext.routine(uuid: ref.uuid) {
                    RoutineDetailView(routine: routine)
                }
            }
            // Registered at the stack root, NOT inside RoutineCatalogScreen:
            // a value destination declared on a screen that is itself pushed
            // (the catalog rides navigationDestination(isPresented:)) failed
            // to resolve in production — template taps hit SwiftUI's
            // missing-destination placeholder (build 33).
            .navigationDestination(for: RoutineTemplate.self) { template in
                RoutineTemplateDetailScreen(template: template, path: $path) { routine in
                    // A template is complete on arrival, so return to the
                    // library with the new card highlighted rather than
                    // pushing into an empty-feeling detail (Dave,
                    // 2026-07-15). Popping the whole path also clears the
                    // catalog beneath, so Back is never stranded.
                    revealNewCard = false     // hold the card out for the entrance beat
                    newlyAdded = routine.persistentModelID
                    path = NavigationPath()
                }
            }
            .overlay {
                if routines.isEmpty {
                    ContentUnavailableView(
                        "No Routines",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Create your first routine to get started.")
                    )
                }
            }
            // The + pushes the routine catalog (#223) — the same
            // grammar as the library tabs: adding starts from a
            // browsable catalog, with blank creation as its first row.
            // A PATH entry, not isPresented (Dave, build 44): the
            // catalog appends templates/routines to this same path,
            // and a value appended beneath a boolean-presented screen
            // replaces it transition-less and double-pops on back.
            .navigationDestination(for: RoutineCatalogDestination.self) { _ in
                RoutineCatalogScreen(path: $path)
            }
        }
        .revealRoot(tab: "routines", atRoot: path.isEmpty)
        // Operator's outcome navigation: a touched routine pushes by its
        // stable uuid (RoutineRef is registered at this stack root, per
        // the #262/#291 laws). The path resets first so the result is
        // one Back from the list, never stacked under stale screens.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusOperatorShow)) { note in
            guard let destination = note.object as? OperatorDestination,
                  case .routine(let uuid) = destination
            else { return }
            path = NavigationPath()
            path.append(RoutineRef(uuid: uuid))
        }
        // Routine creates / deletes / reorders reach GitHub when you leave the
        // tab. Debounced + dirty-gated (see requestSync).
        .syncsProgramOnClose()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                AppMenuKey()
                Spacer()
                HeaderIconButton(systemImage: "plus", accessibilityLabel: "New routine", identifier: "newRoutineButton") {
                    // Root-only affordance, so emptiness doubles as the
                    // double-tap guard (the addTemplateButton class): a
                    // second tap during the push must not stack a
                    // second catalog.
                    guard path.isEmpty else { return }
                    path.append(RoutineCatalogDestination())
                }
            }
            Text("Routines")
                .font(.system(.title, weight: .bold))
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// The list, minus the just-added card while it's still held out for its
    /// entrance (revealNewCard == false). Once `newlyAdded` clears, the
    /// filter is a no-op, so the steady state shows everything.
    private var displayedRoutines: [Routine] {
        routines.filter { $0.persistentModelID != newlyAdded || revealNewCard }
    }

    private func deleteRoutine(_ routine: Routine) {
        modelContext.delete(routine)
        reindexRoutines()
    }

    private func moveRoutines(from source: IndexSet, to destination: Int) {
        // Reorder over the SAME collection the ForEach displays: `.onMove`
        // hands indices into `displayedRoutines`, so basing the move on the
        // full `routines` would mis-map during the brief entrance window
        // where the two diverge. In the steady state they're identical.
        var reordered = displayedRoutines
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, routine) in reordered.enumerated() {
            routine.order = index
        }
    }

    private func reindexRoutines() {
        for (index, routine) in routines.enumerated() {
            routine.order = index
        }
    }
}

/// 44 pt square raised icon key used in tab headers (Quiet Arcade:
/// header icon buttons are neutral secondary keys — supersedes #202's
/// green header +; green's scope tightened to true data and in-list
/// creation rows).
struct HeaderIconButton: View {
    let systemImage: String
    /// Spoken VoiceOver name for the action (required — the glyph alone reads
    /// as its raw SF Symbol name, e.g. "slider horizontal 3").
    let accessibilityLabel: String
    var identifier: String?
    /// Glyph tint; defaults to the neutral header ink. The favorite star
    /// passes `Theme.accent` when lit (green = the user's own data).
    var tint: Color = Theme.textSecondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(.raisedKey())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier ?? systemImage)
    }
}

/// Plain content, deliberately NOT a Button: activation belongs to
/// SwipeRevealRow's onTap (see the component contract — a Button here
/// fired on reveal-drag release and closed the row it opened).
private struct RoutineCard: View {
    let routine: Routine
    /// True for the routine just added from a template — plays a one-shot
    /// entrance flash so the eye lands on it (Dave, 2026-07-15).
    var justAdded: Bool = false
    /// 1 at the peak of the entrance flash, animating to 0 at rest.
    @State private var entrance: Double = 0
    /// The deferred flash beat (it fires just after the card fades in);
    /// cancelled on disappear so it can't light onto a recycled row.
    @State private var flashTask: Task<Void, Never>?
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    private var availableEquipmentNames: Set<String> {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)?.memberNames ?? []
    }

    private var estimateText: String {
        let minutes = max(5, Int((Double(routine.estimatedSeconds) / 300).rounded()) * 5)
        return "~\(minutes) min"
    }

    /// Up to three equipment pills plus a "+N" overflow — the taller
    /// card (#238) affords more than the old single row did.
    private var pills: [String] {
        let names = routine.equipmentNames
        guard !names.isEmpty else { return ["bodyweight"] }
        if names.count > 3 {
            return Array(names.prefix(3)) + ["+\(names.count - 3)"]
        }
        return names
    }

    /// A gear pill the active library doesn't have renders in notes
    /// amber (flag-don't-hide): the card still shows, but a glance says
    /// "not here". The synthetic "+N" and "bodyweight" pills are neutral.
    private func pillUnavailable(_ pill: String) -> Bool {
        guard pill != "bodyweight", !pill.hasPrefix("+") else { return false }
        return !availableEquipmentNames.contains(pill)
    }

    /// The routine's exercises, resolved (a broken reference drops out).
    private var exercises: [Exercise] {
        routine.sortedGroups.flatMap(\.sortedExercises).compactMap(\.exercise)
    }
    private var hasExercises: Bool { !exercises.isEmpty }

    /// A cardio routine tracks distance or pace throughout (Running,
    /// Walking, Cycling, Rowing, the console machines) — where a muscle line
    /// would only say "full body". Stretches and strength keep their real
    /// muscles.
    private var isCardio: Bool {
        hasExercises && exercises.allSatisfy {
            $0.metricProfile.contains(.distance) || $0.metricProfile.contains(.pace)
        }
    }

    /// Row 2's trailing text: the trained muscles, "cardio" for a pure
    /// cardio routine, or an empty-state note.
    private var descriptor: String {
        guard hasExercises else { return "no exercises yet" }
        return isCardio ? "cardio" : musclesLine
    }

    private var musclesLine: String {
        let present = Set(exercises.map(\.muscleGroup))
        let ordered = MuscleGroup.allCases.filter { present.contains($0) }
        guard !ordered.isEmpty else { return "full body" }
        return ordered.map { $0.displayName.lowercased() }.joined(separator: " · ")
    }

    private var isUnscheduled: Bool { routine.schedule.normalized == .unscheduled }
    private var cadenceLabel: String { isUnscheduled ? "anytime" : routine.schedule.shortLabel }
    private var scheduleColor: Color { isUnscheduled ? Theme.textFaint : Theme.textSecondary }

    /// Gear rides its own row as soft tags. Suppressed for a gearless card:
    /// an empty routine, or a run/walk whose only "gear" is bodyweight
    /// (Dave, 2026-07-16).
    private var showsGear: Bool {
        hasExercises && !(isCardio && routine.equipmentNames.isEmpty)
    }

    /// The routine's own one-line description, when it has a non-empty one
    /// (seeded from a catalog template on add). This takes the card's
    /// description row; without it the row falls back to `descriptor`.
    private var routineSummary: String? {
        guard let s = routine.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return s
    }

    /// The facts line: calendar cadence · time estimate. One `Text` so it
    /// truncates as a unit; the description and gear ride their own rows.
    private var factsLine: Text {
        let line = Text(Image(systemName: "calendar")).foregroundStyle(scheduleColor)
            + Text(" \(cadenceLabel)").foregroundStyle(scheduleColor)
        guard hasExercises else { return line }
        return line + Text(" · \(estimateText)").foregroundStyle(Theme.textFaint)
    }

    /// A clean spoken label for the facts line — the raw concatenated `Text`
    /// would have VoiceOver read the calendar glyph and the "·"/"~" aloud.
    private var factsAccessibilityLabel: String {
        hasExercises ? "\(cadenceLabel), \(estimateText)" : cadenceLabel
    }

    var body: some View {
        // Three rows (Dave, 2026-07-16): identity; the description (the
        // routine's own summary if it has one, else what it works); then
        // the facts line (calendar cadence · estimate) with gear soft tags.
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(routine.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            // Description row: the routine's own line if it has one (the
            // catalog voice, carried into the library), else what it works.
            if let summary = routineSummary {
                Text(summary)
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            } else {
                Text(descriptor)
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            // Facts + gear on one row: calendar cadence · estimate, then the
            // gear as soft tags (filled, no stroke — a stroked capsule read
            // as a button; amber still flags gear you don't have).
            HStack(spacing: 8) {
                factsLine
                    .font(.system(.caption))
                    .lineLimit(1)
                    .accessibilityLabel(factsAccessibilityLabel)
                if showsGear {
                    ForEach(pills, id: \.self) { pill in
                        let unavailable = pillUnavailable(pill)
                        Text(pill)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(unavailable ? Theme.notes : Theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(
                                unavailable ? Theme.notes.opacity(0.14) : Theme.surfaceRaised,
                                in: Capsule()
                            )
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
        // Entrance: the green (creation) ring lights just AFTER the card has
        // faded into the list (the list handles the fade + push-down), then
        // fades out. No scaling — a card scaled past its row width clipped
        // its own edges until it settled (Dave, 2026-07-16).
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.accent, lineWidth: 2)
                .opacity(entrance)
        )
        .onChange(of: justAdded, initial: true) { _, isNew in
            guard isNew else { return }
            flashTask?.cancel()
            flashTask = Task { @MainActor in
                // Let the fade-in land before the ring lights.
                try? await Task.sleep(for: .milliseconds(340))
                guard !Task.isCancelled else { return }
                entrance = 1
                withAnimation(.easeOut(duration: 0.9)) { entrance = 0 }
            }
        }
        .onDisappear { flashTask?.cancel() }
    }
}
