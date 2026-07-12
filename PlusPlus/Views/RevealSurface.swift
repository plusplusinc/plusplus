import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PlusPlusKit

/// The app-level surface beneath the reveal drawer (replaces the pushed
/// `AppMenuScreen` + `SettingsScreen`). Settings is folded in: the
/// most-used controls live inline (appearance, units, GitHub + calendar
/// sync, the active equipment library as the hero card); the rarer things
/// are tiles that open bottom-sheet trays (data, Apple Health, what's new,
/// about). Left-aligned column so nothing hides under the app's peeking
/// sliver on the right.
struct RevealSurface: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw = WeightUnit.lb.rawValue
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""
    /// Set once the Health ask has been made this install — the tile sub
    /// flips to "connected" (HealthKit hides read authorization, so this
    /// is the honest signal the app has).
    @AppStorage("healthAccessRequested") private var healthRequested = false

    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]

    @State private var sync = GitHubSyncCoordinator.shared
    @State private var calendar = CalendarSyncCoordinator.shared

    @State private var activeTray: Tray?
    /// Work queued behind a closing tray — run in the tray's onDismiss so
    /// we never stack two presentations in the same frame (the file
    /// dialogs and the pushed screens both present from this view).
    @State private var pendingPush: Push?
    @State private var pendingExport = false
    @State private var pendingImport = false
    @State private var activePush: Push?

    // Data plumbing (moved from SettingsScreen).
    @State private var showingExporter = false
    @State private var exportDocument: InterchangeDocument?
    @State private var showingImporter = false
    @State private var importResultMessage: String?
    @State private var dataError: String?

    enum Tray: String, Identifiable { case library, sync, calendar, data, whatsNew, about; var id: String { rawValue } }
    enum Push: String, Identifiable { case equipment; var id: String { rawValue } }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                identity
                libraryCard
                    .padding(.top, 26)
                appearanceSection
                    .padding(.top, 22)
                unitsSection
                    .padding(.top, 18)
                syncSection
                    .padding(.top, 22)
                tiles
                    .padding(.top, 20)
                footer
                    .padding(.top, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 24)
            .padding(.trailing, 96)
            .padding(.top, 60)
            .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .sheet(item: $activeTray, onDismiss: {
            // One presentation per frame: fire whatever the tray queued
            // only after it has fully dismissed.
            if let push = pendingPush { pendingPush = nil; activePush = push }
            else if pendingExport { pendingExport = false; prepareExport() }
            else if pendingImport { pendingImport = false; showingImporter = true }
        }) { tray in
            trayContent(tray)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.sheetRadius + 2)
                .presentationBackground(Theme.surface)
        }
        // Two sheet(item:) modifiers share this view; the pending-queue
        // above guarantees activeTray is nil before activePush is set, so
        // they never present in the same frame.
        .sheet(item: $activePush) { push in
            NavigationStack {
                switch push {
                case .equipment: CatalogBrowseScreen(kind: .equipment, setupMode: true)
                }
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "plusplus-export"
        ) { result in
            if case .failure(let error) = result { dataError = error.localizedDescription }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .alert("Import Complete", isPresented: Binding(
            get: { importResultMessage != nil },
            set: { if !$0 { importResultMessage = nil } }
        )) {
            Button("OK") { importResultMessage = nil }
        } message: { Text(importResultMessage ?? "") }
        .alert("Something Went Wrong", isPresented: Binding(
            get: { dataError != nil },
            set: { if !$0 { dataError = nil } }
        )) {
            Button("OK") { dataError = nil }
        } message: { Text(dataError ?? "") }
    }

    // MARK: - Identity

    private var identity: some View {
        HStack(spacing: 11) {
            Text("++")
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
            Text("PlusPlus")
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: - Active-library card (the hero)

    private var libraryCard: some View {
        let items = activeLibrary?.members.count ?? 0
        let itemsText = items == 0 ? "bodyweight" : "\(items) item\(items == 1 ? "" : "s")"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ACTIVE LIBRARY")
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .kerning(0.5)
                Spacer()
                Button { openTray(.library) } label: {
                    Text("Switch")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderStrong))
                }
                .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: 8, travel: 3))
                .accessibilityIdentifier("revealSwitchLibrary")
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(activeLibrary?.name ?? "Home")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("· \(itemsText)")
                    .font(.system(.subheadline))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("\(exerciseCount(for: activeLibrary)) exercises · \(routineCount(for: activeLibrary)) routines")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius - 2))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius - 2).strokeBorder(Theme.borderStrong))
        .raisedPlate(cornerRadius: Theme.cardRadius - 2)
    }

    // MARK: - Appearance / Units

    private var appearanceSection: some View {
        // Explicit System / Light / Dark order (handoff), mapped back to
        // the enum's raw values.
        let order: [AppAppearance] = [.system, .light, .dark]
        return VStack(alignment: .leading, spacing: 7) {
            SheetSectionLabel("APPEARANCE")
            SegmentedTabs(
                options: order.map(\.label),
                selectedIndex: Binding(
                    get: { order.firstIndex(of: AppAppearance(rawValue: appearanceRaw) ?? .system) ?? 0 },
                    set: { appearanceRaw = order[$0].rawValue }
                )
            )
        }
    }

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SheetSectionLabel("UNITS")
            SegmentedTabs(
                options: ["lb", "kg"],
                selectedIndex: Binding(
                    get: { weightUnitRaw == WeightUnit.kg.rawValue ? 1 : 0 },
                    set: { weightUnitRaw = ($0 == 1 ? WeightUnit.kg : WeightUnit.lb).rawValue }
                )
            )
        }
    }

    // MARK: - Sync rows (GitHub + Calendar)

    /// GitHub + Calendar triggers under one SYNC header; the rows drop the
    /// redundant "sync" word now that the header carries it.
    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetSectionLabel("SYNC")
            syncRow
            calendarRow
        }
    }

    private var syncRow: some View {
        let connected = sync.isConnected
        // Red "disconnected" only when a live connection broke or a connect
        // attempt failed; a clean never-connected install reads as neutral
        // gray with no trailing word, and so does an unconfigured build (gate
        // on .disconnected, so a stale fault flag can't paint it red). Green
        // when live, also with no trailing word.
        let faulted = sync.connection == .disconnected && sync.faulted
        let dot: Color = connected ? Theme.accent : (faulted ? Theme.destructive : Theme.textFaint)
        return Button {
            openTray(.sync)
        } label: {
            HStack(spacing: 9) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Image("GitHubMark").resizable().scaledToFit().frame(width: 16, height: 16)
                Text("GitHub")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                if faulted {
                    Text("disconnected")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: 11, travel: 3))
        .accessibilityIdentifier("revealSyncRow")
    }

    private var calendarRow: some View {
        let on = calendar.isEnabled
        return statusRow(
            dot: on ? Theme.accent : Theme.textFaint,
            title: "Calendar",
            status: on ? "on" : "off",
            identifier: "revealCalendarRow"
        ) { openTray(.calendar) }
    }

    private func statusRow(dot: Color, title: String, status: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Text(status)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: 11, travel: 3))
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Tiles

    private var tiles: some View {
        let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        return LazyVGrid(columns: columns, spacing: 6) {
            tile(title: "Data", sub: "export · import", subColor: Theme.textFaint, id: "revealDataTile") { openTray(.data) }
            tile(
                title: "Health",
                sub: healthRequested ? "connected" : "connect",
                subColor: healthRequested ? Theme.accent : Theme.textFaint,
                id: "revealHealthTile"
            ) { connectHealth() }
            tile(title: "What's new", sub: "build \(build)", subColor: Theme.textFaint, id: "revealWhatsNewTile") { openTray(.whatsNew) }
            tile(title: "About", sub: "links · feedback", subColor: Theme.textFaint, id: "revealAboutTile") { openTray(.about) }
        }
    }

    private func tile(title: String, sub: String, subColor: Color, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(sub)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(subColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: - Footer

    private var footer: some View {
        Text("++ \(version) · build \(build)")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Trays

    @ViewBuilder
    private func trayContent(_ tray: Tray) -> some View {
        switch tray {
        case .library:
            LibraryTray(
                exerciseCount: { exerciseCount(for: $0) },
                routineCount: { routineCount(for: $0) },
                onEditGear: { queuePush(.equipment) }
            )
        case .sync:
            GitHubSyncTray()
        case .calendar:
            CalendarTray(calendar: calendar, routines: routines)
        case .data:
            // Queue + close the tray; the exporter/importer presents in the
            // tray's onDismiss so it never races the tray's own dismissal.
            DataTray(
                onExport: { pendingExport = true; activeTray = nil },
                onImport: { pendingImport = true; activeTray = nil }
            )
        case .whatsNew:
            WhatsNewTray()
        case .about:
            AboutTray(version: version, build: build)
        }
    }

    // MARK: - Actions

    private func openTray(_ tray: Tray) { activeTray = tray }

    /// Queue a full-screen push and dismiss the tray; the push presents in
    /// the tray's onDismiss so two sheets never race in one frame.
    private func queuePush(_ push: Push) {
        pendingPush = push
        activeTray = nil
    }

    private func connectHealth() {
        HealthAccess.requestEverything { healthRequested = true }
    }

    // MARK: - Downstream counts (equipment → exercises → routines)

    /// Exercises performable with a library's gear (bodyweight always
    /// counts). Availability = the ExerciseFilterState rule, so this reads
    /// the same as the catalog.
    private func exerciseCount(for library: EquipmentLibrary?) -> Int {
        let names = library?.memberNames ?? []
        return allExercises.filter { ExerciseFilterState.missingEquipment(for: $0, available: names).isEmpty }.count
    }

    /// Routines every exercise of which is performable with the gear —
    /// "what this library unlocks". Empty routines don't count.
    private func routineCount(for library: EquipmentLibrary?) -> Int {
        let names = library?.memberNames ?? []
        return routines.filter { routine in
            let exercises = routine.sortedGroups.flatMap { $0.sortedExercises }.compactMap { $0.exercise }
            return !exercises.isEmpty && exercises.allSatisfy {
                ExerciseFilterState.missingEquipment(for: $0, available: names).isEmpty
            }
        }.count
    }

    // MARK: - Data (moved from SettingsScreen)

    private func prepareExport() {
        do {
            let bundle = try InterchangeMapping.exportBundle(
                context: modelContext,
                units: WeightUnit(rawValue: weightUnitRaw) ?? .lb
            )
            exportDocument = InterchangeDocument(data: try InterchangeCodec.encode(bundle))
            showingExporter = true
        } catch {
            dataError = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                dataError = "Couldn't read the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            let bundle = try InterchangeCodec.decode(ExportBundle.self, from: data)
            let summary = try InterchangeMapping.importBundle(bundle, context: modelContext)
            if let units = bundle.units, units.rawValue != weightUnitRaw {
                weightUnitRaw = units.rawValue
            }
            importResultMessage = summaryText(summary)
        } catch let InterchangeMapping.ImportError.invalidBundle(issues) {
            dataError = "Invalid file:\n" + issues.prefix(5).map(\.description).joined(separator: "\n")
        } catch InterchangeCodec.CodecError.unsupportedSchemaVersion(let version) {
            dataError = "This file uses schema v\(version); this app understands up to v\(Interchange.schemaVersion). Update PlusPlus."
        } catch {
            dataError = error.localizedDescription
        }
    }

    private func summaryText(_ summary: InterchangeMapping.ImportSummary) -> String {
        var lines: [String] = []
        if summary.exercisesCreated + summary.exercisesUpdated > 0 {
            lines.append("Exercises: \(summary.exercisesCreated) added, \(summary.exercisesUpdated) updated")
        }
        if summary.routinesCreated + summary.routinesReplaced > 0 {
            lines.append("Routines: \(summary.routinesCreated) added, \(summary.routinesReplaced) replaced")
        }
        if summary.equipmentConfigured > 0 {
            lines.append("Equipment: \(summary.equipmentConfigured) configured")
        }
        if summary.librariesCreated + summary.librariesReplaced > 0 {
            lines.append("Libraries: \(summary.librariesCreated) added, \(summary.librariesReplaced) updated")
        }
        lines.append("Sessions: \(summary.sessionsAdded) added, \(summary.sessionsSkipped) already present")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Raised base-plate (for non-button cards that sit proud)

private extension View {
    /// A 3 pt base plate under a card, mirroring RaisedKeyStyle's plate so
    /// a static card reads as part of the same key family without pressing.
    func raisedPlate(cornerRadius: CGFloat) -> some View {
        self
            .padding(.bottom, 3)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Theme.border)
                    .padding(.top, 3)
            }
    }
}

// MARK: - Equipment-library tray (switch + create + curate)

/// The reveal's library tray: pick the active library (radio rows with the
/// downstream cascade), create a new one, or jump to gear curation. Rename
/// and delete stay on the Equipment tab's fuller tray (`EquipmentLibraryTray`).
private struct LibraryTray: View {
    let exerciseCount: (EquipmentLibrary?) -> Int
    let routineCount: (EquipmentLibrary?) -> Int
    let onEditGear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    @State private var promptingNew = false
    @State private var newName = ""

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Equipment library", closeOnly: true, action: { dismiss() })
            // Pithy line (no em dash, per the copy law).
            Text("What you have decides what you can train. Switch sets any time, without touching your history.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(libraries) { library in
                        libraryRow(library)
                    }
                    // Creation is green (the theme's creation-affordance rule).
                    Button {
                        newName = ""
                        promptingNew = true
                    } label: {
                        HStack(spacing: 9) {
                            Text("+")
                                .font(.system(size: 17, weight: .bold, design: .monospaced))
                            Text("New library")
                                .font(.system(.subheadline, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        )
                    }
                    .accessibilityIdentifier("revealNewLibrary")

                    // Gear curation for the active library (the old
                    // "My equipment"), kept a tap away here.
                    Button(action: onEditGear) {
                        HStack {
                            Text("Choose your gear")
                                .font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(.caption2, weight: .bold))
                                .foregroundStyle(Theme.textFaint)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong))
                    }
                    .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
                    .accessibilityIdentifier("revealChooseGear")
                    .padding(.top, 2)
                }
                .padding(.top, 14)
                .sensoryFeedback(.selection, trigger: activeLibraryID)
            }
        }
        .padding(.horizontal, 18)
        .presentationDetents([.medium, .large])
        .alert("New library", isPresented: $promptingNew) {
            TextField("Hotel, Garage, Office…", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { createLibrary() }
        } message: {
            Text("Starts empty. Pick its gear from the catalog.")
        }
    }

    private func libraryRow(_ library: EquipmentLibrary) -> some View {
        let selected = library === activeLibrary
        let items = library.members.count
        let itemsText = items == 0 ? "bodyweight only" : "\(items) item\(items == 1 ? "" : "s")"
        return Button {
            activeLibraryID = library.uuid.uuidString
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(library.name)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("\(itemsText) · \(exerciseCount(library)) exercises · \(routineCount(library)) routines")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.selected)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(selected ? Theme.selectedTint : Theme.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Theme.selectedRing : Theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("revealLibraryRow-\(library.name)")
    }

    private func createLibrary() {
        let base = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        newName = ""
        guard !base.isEmpty else { return }
        var name = base
        var suffix = 2
        while libraries.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            name = "\(base) \(suffix)"
            suffix += 1
        }
        let library = EquipmentLibrary(name: name, order: (libraries.map(\.order).max() ?? -1) + 1)
        modelContext.insert(library)
        activeLibraryID = library.uuid.uuidString
    }
}

// MARK: - Calendar sync tray

/// The calendar feature (#333) as a tray: the opt-in toggle, a start-time
/// picker, and the same guidance/error copy the Settings section carried.
private struct CalendarTray: View {
    let calendar: CalendarSyncCoordinator
    let routines: [Routine]
    @Environment(\.dismiss) private var dismiss

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { calendar.isEnabled },
            set: { on in
                Task { @MainActor in
                    if on { await calendar.enable(routines: routines) }
                    else { await calendar.disableAndRemove() }
                }
            }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = CalendarSyncSettings.hour
                comps.minute = CalendarSyncSettings.minute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                Task { @MainActor in
                    calendar.updateTime(
                        hour: comps.hour ?? CalendarSyncSettings.defaultHour,
                        minute: comps.minute ?? CalendarSyncSettings.defaultMinute,
                        routines: routines
                    )
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Calendar sync", closeOnly: true, action: { dismiss() })

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: enabledBinding) {
                    Text("Add scheduled workouts")
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.selected)
                .accessibilityIdentifier("calendarSyncToggle")

                if calendar.isEnabled {
                    Divider().overlay(Theme.border)
                    HStack {
                        Text("Start time")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .accessibilityIdentifier("calendarStartTime")
                    }
                }
            }
            .padding(14)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
            .padding(.top, 16)

            if calendar.accessDenied {
                Text("PlusPlus needs calendar access. Turn it on in iOS Settings \u{2192} Privacy \u{2192} Calendars.")
                    .font(.system(.caption))
                    .foregroundStyle(Theme.destructive)
                    .padding(.top, 6)
            }
            if calendar.unavailable {
                Text("Couldn't create the calendar. Add an account with a writable calendar in iOS Settings, then try again.")
                    .font(.system(.caption))
                    .foregroundStyle(Theme.destructive)
                    .padding(.top, 6)
            }
            Text("Fixed-weekday routines get a recurring event in a \u{201C}++ Workouts\u{201D} calendar, each with a link that starts the workout. To remove them, turn this off or delete that calendar.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Data tray

private struct DataTray: View {
    let onExport: () -> Void
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Data", closeOnly: true, action: { dismiss() })
            Text("Interchange schema v\(Interchange.schemaVersion). Exercises + routines + history as JSON.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 4)

            VStack(spacing: 10) {
                // The parent closes this tray (activeTray = nil) and defers
                // the file dialog to onDismiss; don't dismiss here too.
                dataKey("Export data…", systemImage: "arrow.up.doc", action: onExport)
                dataKey("Import data…", systemImage: "arrow.down.doc", action: onImport)
            }
            .padding(.top, 16)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .presentationDetents([.medium])
    }

    private func dataKey(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(.footnote, weight: .semibold))
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: 11, travel: 3))
    }
}

// MARK: - What's new tray

private struct WhatsNewTray: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "What's new", closeOnly: true, action: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(WhatsNew.entries.enumerated()), id: \.offset) { index, entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BUILD \(entry.build)")
                                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                .foregroundStyle(Theme.textFaint)
                                .kerning(0.5)
                            Text(entry.notes)
                                .font(.system(.footnote))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 11)
                        if index < WhatsNew.entries.count - 1 {
                            Divider().overlay(Theme.border)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 18)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - About tray

private struct AboutTray: View {
    let version: String
    let build: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "About", closeOnly: true, action: { dismiss() })
            Text("PlusPlus \(version) · build \(build)")
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
            Text("The hackable workout tracker for incrementing yourself. Your training data is a git repo you own.")
                .font(.system(.footnote))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 6)

            SheetSectionLabel("LINKS")
                .padding(.top, 20)
            VStack(spacing: 0) {
                linkRow("plusplus.fit", url: "https://plusplus.fit")
                Divider().overlay(Theme.border)
                linkRow("Source on GitHub", url: "https://github.com/plusplusinc/plusplus")
            }
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.border))

            SheetSectionLabel("FEEDBACK")
                .padding(.top, 20)
            VStack(spacing: 0) {
                linkRow("Report an issue or idea", url: "https://github.com/plusplusinc/plusplus/issues/new")
                Divider().overlay(Theme.border)
                linkRow("Email", url: "mailto:mr.david.j.cole@gmail.com")
            }
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.border))

            Text("Opens GitHub or Mail. The app itself never phones home.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .presentationDetents([.medium, .large])
    }

    private func linkRow(_ title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Text(title)
                    .font(.system(.subheadline))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - What's-new data (moved from AppMenuScreen)

/// Per-build highlights, newest first — curated by hand at each TestFlight
/// dispatch (one line each, no obligation words).
enum WhatsNew {
    static let entries: [(build: String, notes: String)] = [
        ("61", "Scheduled workouts on your calendar · one tap on the event starts the session · works with Apple and Google"),
        ("55", "Sync your program and history to a GitHub repo you own · restore-safe on a new phone"),
        ("48", "Equipment libraries: keep a set for home and another for the road · switch and the whole app follows · your gear travels with you to a new phone"),
        ("46", "Cardio speaks its own numbers · splits, watts, damper, incline · intervals with their own rest · choose what any exercise tracks · heart rate on screen"),
        ("45", "The ++ key on every tab · catalog pages push and pop one step at a time"),
        ("44", "The ++ wears its key"),
        ("43", "Keys travel deeper · the +1 gets its moment · swipe actions in full color · our own chrome, corner to corner"),
        ("42", "Quiet Arcade: buttons press like real keys · your week as blocks on Today · Log set pops a +1 · rest gains +30s"),
    ]
}

// MARK: - Interchange document (moved from SettingsScreen)

/// Minimal FileDocument wrapper so fileExporter can hand off encoded
/// interchange data.
struct InterchangeDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
