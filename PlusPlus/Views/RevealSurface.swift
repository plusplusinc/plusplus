import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import HealthKit
import UIKit
import PlusPlusKit

/// The app-level surface beneath the reveal drawer (replaces the pushed
/// `AppMenuScreen` + `SettingsScreen`). Settings is folded in: the
/// most-used controls live inline (appearance, units, the GitHub / Health /
/// calendar sync rows, the active equipment library as the hero card); the
/// rarer things are tiles that open bottom-sheet trays (data, what's new,
/// about). Left-aligned column so nothing hides under the app's peeking
/// sliver on the right.
struct RevealSurface: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(RevealController.self) private var reveal
    @Environment(ViewContext.self) private var viewContext
    // Appearance now lives in the Settings tray (SettingsTray owns that
    // @AppStorage). The weight unit stays here — export/import read it.
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw = WeightUnit.lb.rawValue
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]

    @State private var sync = GitHubSyncCoordinator.shared
    @State private var health = HealthSyncCoordinator.shared
    @State private var calendar = CalendarSyncCoordinator.shared

    /// Operator's conductor — created LAZILY on first use (drawer open
    /// or hero tap), never at app init: the model session and thread
    /// load shouldn't cost a launch that never opens the drawer.
    @State private var operatorController: OperatorController?
    @State private var operatorAvailability = OperatorAvailability.current()

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

    enum Tray: String, Identifiable { case operatorChat, library, sync, health, calendar, settings, data, whatsNew, about; var id: String { rawValue } }
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
                operatorHero
                    .padding(.top, 26)
                librarySection
                    .padding(.top, 26)
                syncSection
                    .padding(.top, 26)
                // Separator between the sync rows and the bottom tile
                // group (Dave, build-78).
                Divider()
                    .overlay(Theme.border)
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
                case .equipment: EquipmentCatalogScreen(setupMode: true)
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

    // MARK: - Operator card (the hero)

    /// Operator takes the hero slot (Dave, 2026-07-15); the active
    /// library demotes to a row below. Always visible — unavailable
    /// states show a quiet status word here and explain themselves
    /// inside the tray, in Operator's voice. Redesigned in the build-85
    /// round (Dave: caption + title + snippet read "operator operator
    /// operator"): one face glyph with ++ eyes, the name once, and the
    /// designed tagline wrapping beneath — no dot (dots mean sync
    /// state), no last-reply snippet.
    private var operatorHero: some View {
        Button { openOperator() } label: {
            HStack(alignment: .center, spacing: 12) {
                OperatorFaceGlyph(size: 38, ready: operatorAvailability == .ready)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Operator")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        if let word = operatorAvailability.statusWord {
                            Text(word)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Theme.textFaint)
                        }
                    }
                    Text(OperatorPersona.heroTagline)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius - 2))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius - 2).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: Theme.cardRadius - 2, travel: 3))
        .accessibilityIdentifier("operatorHeroCard")
        // Availability flips in Settings, outside the app; the session
        // prewarms as soon as the drawer opens so the first turn is fast.
        .onChange(of: reveal.isOpen) { _, isOpen in
            guard isOpen else { return }
            operatorAvailability = .current()
            if operatorAvailability == .ready {
                ensureOperatorController().prewarmIfReady()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { operatorAvailability = .current() }
        }
    }

    @discardableResult
    private func ensureOperatorController() -> OperatorController {
        if let operatorController { return operatorController }
        let controller = OperatorController(context: modelContext)
        controller.contextLine = { [weak viewContext] in viewContext?.line }
        controller.hasWorkoutHistory = { [modelContext] in
            ((try? modelContext.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0) > 0
        }
        operatorController = controller
        return controller
    }

    private func openOperator() {
        ensureOperatorController()
        openTray(.operatorChat)
    }

    // MARK: - Active-library row (demoted from the hero slot)

    private var librarySection: some View {
        let items = activeLibrary?.members.count ?? 0
        let itemsText = items == 0 ? "bodyweight" : "\(items) item\(items == 1 ? "" : "s")"
        return VStack(alignment: .leading, spacing: 10) {
            SheetSectionLabel("KIT")
            statusRow(
                dot: nil,
                icon: {
                    Image(systemName: "dumbbell")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 16, height: 16)
                },
                title: activeLibrary?.name ?? EquipmentLibrary.defaultName,
                status: itemsText,
                identifier: "revealLibraryRow"
            ) { openTray(.library) }
        }
    }

    // MARK: - Sync rows (GitHub + Calendar)

    /// GitHub + Health + Calendar triggers under one SYNC header (each syncs
    /// to an external system); the rows drop the redundant "sync" word now
    /// that the header carries it.
    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetSectionLabel("SYNC")
            syncRow
            healthRow
            calendarRow
        }
        // The Health write grant only ever changes through the system sheet
        // or iOS Settings, outside this view — re-read it whenever the surface
        // reappears AND on foreground return (onAppear doesn't re-fire when the
        // app resumes to an already-visible drawer).
        .onAppear { health.refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { health.refreshStatus() }
        }
    }

    private var syncRow: some View {
        let connected = sync.isConnected
        // Trailing status word: "connected" (green) when live, "disconnected"
        // (red) when a connect attempt failed or a live connection broke. A
        // clean never-connected install reads as neutral gray with no word, and
        // so does an unconfigured build (red gated on .disconnected, so a stale
        // fault flag can't paint it red).
        let faulted = sync.connection == .disconnected && sync.faulted
        let dot: Color = connected ? Theme.accent : (faulted ? Theme.destructive : Theme.textFaint)
        let secondary: String? = connected ? "connected" : (faulted ? "disconnected" : nil)
        return statusRow(
            dot: dot,
            icon: { Image("GitHubMark").resizable().scaledToFit().frame(width: 16, height: 16).accessibilityHidden(true) },
            title: "GitHub",
            status: secondary,
            identifier: "revealSyncRow"
        ) { openTray(.sync) }
    }

    /// Honest Health status: green "on" ONLY when the OS actually grants the
    /// workout write (the one authorization HealthKit will reveal). Enabled
    /// but never granted reads neutral "connect"; a denied write is red; a
    /// user-disabled or unavailable integration is neutral "off"/"unavailable".
    private var healthRow: some View {
        let dot: Color
        let word: String
        if !health.isAvailable {
            dot = Theme.textFaint; word = "unavailable"
        } else if !health.isEnabled {
            dot = Theme.textFaint; word = "off"
        } else {
            switch health.writeStatus {
            case .sharingAuthorized: dot = Theme.accent; word = "on"
            case .sharingDenied: dot = Theme.destructive; word = "denied"
            default: dot = Theme.textFaint; word = "connect"
            }
        }
        return statusRow(
            dot: dot,
            icon: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 16, height: 16)
            },
            title: "Health",
            status: word,
            identifier: "revealHealthRow"
        ) { openTray(.health) }
    }

    private var calendarRow: some View {
        let on = calendar.isEnabled
        return statusRow(
            dot: on ? Theme.accent : Theme.textFaint,
            icon: {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 16, height: 16)
            },
            title: "Calendar",
            status: on ? "on" : "off",
            identifier: "revealCalendarRow"
        ) { openTray(.calendar) }
    }

    /// A trigger row: an optional status dot (SYNC rows only — a dot means
    /// "state of a connection", so Operator/Library rows pass nil; Dave,
    /// build-85 design round), a leading icon (GitHub mark / SF Symbol),
    /// the name, then a right-aligned status word before the chevron. `status`
    /// is optional so a never-connected GitHub row shows no trailing word.
    private func statusRow<Icon: View>(
        dot: Color?,
        @ViewBuilder icon: () -> Icon,
        title: String,
        status: String?,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let dot {
                    Circle().fill(dot).frame(width: 8, height: 8)
                }
                icon()
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                if let status {
                    Text(status)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: Theme.keyRadius, travel: 3))
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Tiles

    private var tiles: some View {
        let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        // A 2×2 of equal tiles (Dave, build-78): Settings joins the group,
        // and every tile shares one height regardless of caption length.
        return LazyVGrid(columns: columns, spacing: 6) {
            tile(title: "Settings", sub: "appearance · units", subColor: Theme.textFaint, id: "revealSettingsTile") { openTray(.settings) }
            tile(title: "Data", sub: "export · import", subColor: Theme.textFaint, id: "revealDataTile") { openTray(.data) }
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(sub)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(subColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(12)
            // Fixed minimum height + single-line captions keep every tile
            // the same size; "export · import" used to wrap and make Data
            // taller than its neighbors.
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
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
        case .operatorChat:
            // The controller exists by construction (openOperator creates
            // it before presenting); the fallback renders nothing.
            if let operatorController {
                OperatorTray(controller: operatorController)
            } else {
                Color.clear
            }
        case .library:
            // One canonical kit tray everywhere (switch · create · rename ·
            // delete), with the curation shortcut the drawer needs since it
            // is remote from the catalog.
            EquipmentLibraryTray(onEditContents: { queuePush(.equipment) })
        case .sync:
            GitHubSyncTray()
        case .health:
            HealthTray(health: health)
        case .calendar:
            CalendarTray(calendar: calendar, routines: routines)
        case .settings:
            SettingsTray()
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
            lines.append("Kits: \(summary.librariesCreated) added, \(summary.librariesReplaced) replaced")
        }
        lines.append("Sessions: \(summary.sessionsAdded) added, \(summary.sessionsSkipped) already present")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Health sync tray

/// Configure the Apple Health integration: one toggle for the whole thing,
/// plus an honest read-out of the only authorization HealthKit will reveal
/// (the workout WRITE grant). Reads are invisible to us by design, so we
/// never claim more than we can prove.
private struct HealthTray: View {
    let health: HealthSyncCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { health.isEnabled },
            set: { on in on ? health.enable() : health.disable() }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Apple Health", closeOnly: true, action: { dismiss() })

            Text("PlusPlus saves finished workouts to Health and reads heart rate to color your zones, and nothing else. Turning this off stops both on this iPhone. A workout you run from Apple Watch keeps its own Health access.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: enabledBinding) {
                    Text("Use Apple Health")
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.selected)
                .disabled(!health.isAvailable)
                .accessibilityIdentifier("healthSyncToggle")

                if health.isAvailable, health.isEnabled {
                    Divider().overlay(Theme.border)
                    statusBlock
                }
            }
            .padding(14)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
            .padding(.top, 16)

            if !health.isAvailable {
                Text("Apple Health isn't available on this device.")
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.top, 6)
            }

            Text("HealthKit keeps read permission private, so \u{201C}connected\u{201D} reflects the workout-saving grant. To change access later, use iOS Settings \u{2192} Health \u{2192} Data Access.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .presentationDetents([.medium, .large])
        // The grant only ever moves through the system sheet — re-read it
        // when we return from it (or from iOS Settings).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { health.refreshStatus() }
        }
    }

    /// The live authorization read-out under the toggle.
    @ViewBuilder
    private var statusBlock: some View {
        switch health.writeStatus {
        case .sharingAuthorized:
            statusLine(dot: Theme.accent, text: "Connected. Finished workouts are saved to Health.")
        case .sharingDenied:
            VStack(alignment: .leading, spacing: 8) {
                statusLine(dot: Theme.destructive, text: "Saving workouts is turned off in iOS Settings.")
                settingsButton
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                statusLine(dot: Theme.textFaint, text: "Not connected yet. Grant access so PlusPlus can save workouts and read heart rate.")
                Button { health.enable() } label: {
                    Text("Connect")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
                }
                .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: Theme.keyRadius, travel: 3))
                .accessibilityIdentifier("healthConnectButton")
            }
        }
    }

    private func statusLine(dot: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(dot).frame(width: 8, height: 8).padding(.top, 5)
            Text(text)
                .font(.system(.footnote))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var settingsButton: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            Text("Open iOS Settings")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: Theme.keyRadius, travel: 3))
        .accessibilityIdentifier("healthOpenSettingsButton")
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

// MARK: - Settings tray (appearance + units)

/// The two display preferences that used to sit inline on the drawer
/// (Dave, build-78): appearance and units, pulled into their own tray
/// behind the Settings tile so the drawer leads with library + sync.
private struct SettingsTray: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw = WeightUnit.lb.rawValue
    @AppStorage(VoiceCueMode.key) private var voiceCueRaw = VoiceCueMode.off.rawValue
    @AppStorage(VoiceCueVoice.key) private var voiceCueVoiceRaw = ""
    @AppStorage(CountdownCueSetting.key) private var countdownCuesEnabled = true
    /// Enumerating system voices has real cost — snapshot per tray
    /// appearance, not per render.
    @State private var voiceOptions: [VoiceCueVoice.Option] = []

    var body: some View {
        // Explicit System / Light / Dark order (handoff), mapped back to
        // the enum's raw values.
        let order: [AppAppearance] = [.system, .light, .dark]
        return VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Settings", closeOnly: true, action: { dismiss() })

            VStack(alignment: .leading, spacing: 7) {
                SheetSectionLabel("APPEARANCE")
                SegmentedTabs(
                    options: order.map(\.label),
                    selectedIndex: Binding(
                        get: { order.firstIndex(of: AppAppearance(rawValue: appearanceRaw) ?? .system) ?? 0 },
                        set: { appearanceRaw = order[$0].rawValue }
                    )
                )
            }
            .padding(.top, 18)

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
            .padding(.top, 22)

            VStack(alignment: .leading, spacing: 7) {
                SheetSectionLabel("VOICE CUES")
                // Explicit order: most talkative to silent, matching the
                // APPEARANCE idiom of a fixed display order over the
                // enum's declaration order.
                let cueOrder: [VoiceCueMode] = [.always, .refresher, .off]
                SegmentedTabs(
                    options: ["Every time", "Refreshers", "Off"],
                    selectedIndex: Binding(
                        get: { cueOrder.firstIndex(of: VoiceCueMode(rawValue: voiceCueRaw) ?? .off) ?? 2 },
                        set: { voiceCueRaw = cueOrder[$0].rawValue }
                    )
                )
                Text(voiceCueCaption)
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textFaint)

                // The voice picker is dead UI while cues are off.
                if (VoiceCueMode(rawValue: voiceCueRaw) ?? .off) != .off {
                    HStack {
                        Text("Voice")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Menu {
                            Picker("Voice", selection: $voiceCueVoiceRaw) {
                                ForEach(voiceOptions) { option in
                                    Text(option.label).tag(option.id)
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(selectedVoiceLabel)
                                    .font(.system(.subheadline))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(.caption2, weight: .semibold))
                            }
                            .foregroundStyle(Theme.textSecondary)
                        }
                        .accessibilityIdentifier("voiceCueVoicePicker")
                    }
                    .padding(.top, 8)
                    // A picked voice speaks a sample cue so it can be
                    // judged without starting a workout.
                    .onChange(of: voiceCueVoiceRaw) {
                        VoiceCueSpeaker.shared.preview()
                    }
                    Text("Voices come from iOS. Download more under Settings \u{2192} Accessibility \u{2192} Spoken Content \u{2192} Voices.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.top, 22)
            .onAppear { voiceOptions = VoiceCueVoice.options() }

            VStack(alignment: .leading, spacing: 7) {
                SheetSectionLabel("COUNTDOWN CUES")
                Toggle(isOn: $countdownCuesEnabled) {
                    Text("Rest countdown beeps")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.accent)
                .accessibilityIdentifier("countdownCuesToggle")
                Text("A soft beep on the last three seconds of a rest or switch, and a higher tone as the next exercise begins. Plays over the silent switch, and ducks music.")
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.top, 22)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .presentationDetents([.medium, .large])
    }

    /// The current picker label; an identifier whose voice was deleted
    /// from the device reads as the default it will actually fall back
    /// to.
    private var selectedVoiceLabel: String {
        voiceOptions.first { $0.id == voiceCueVoiceRaw }?.label ?? "System default"
    }

    /// The caption explains the SELECTED mode (the segment labels are
    /// too short to carry the refresher definition on their own).
    private var voiceCueCaption: String {
        switch VoiceCueMode(rawValue: voiceCueRaw) ?? .off {
        case .always:
            return "A voice speaks a quick form reminder as each exercise begins. Music ducks while it talks."
        case .refresher:
            return "A voice speaks form reminders only for exercises that are new to you or that you haven't done in a month."
        case .off:
            return "No spoken form reminders."
        }
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
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: Theme.keyRadius, travel: 3))
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
            Text("A hackable workout tracker for incrementing yourself. Your training data is a git repo you own.")
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
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.border))

            SheetSectionLabel("FEEDBACK")
                .padding(.top, 20)
            VStack(spacing: 0) {
                linkRow("Report an issue or idea", url: "https://github.com/plusplusinc/plusplus/issues/new")
                Divider().overlay(Theme.border)
                linkRow("Email", url: "mailto:mr.david.j.cole@gmail.com")
            }
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.border))

            Text("Opens GitHub or Mail. PlusPlus never phones home.")
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - What's-new data (moved from AppMenuScreen)

/// Per-build highlights, newest first — curated by hand at each TestFlight
/// dispatch (one line each, no obligation words).
enum WhatsNew {
    static let entries: [(build: String, notes: String)] = [
        ("108", "Rest countdowns beep the last three seconds, a higher tone starts the next move · the live workout is back on the Dynamic Island and Lock Screen · the set overview colors every exercise: done, now, and up next"),
        ("84", "Operator: chat with your training data behind the ++ key · ask anything, change anything · bulk edits preview before they touch a thing, small ones undo in a tap · the model runs entirely on this phone · and outdoor runs now keep their route: map, splits, and stats on the record"),
        ("61", "Scheduled workouts on your calendar · one tap on the event starts the session · works with Apple and Google"),
        ("55", "Sync your program and history to a GitHub repo you own · restore-safe on a new phone"),
        ("48", "Kits: keep one set of equipment for home and another for the road · switch and the whole app follows · your kit travels with you to a new phone"),
        ("46", "Cardio speaks its own numbers · splits, watts, damper, incline · intervals with their own rest · choose what any exercise tracks · heart rate on screen"),
        ("45", "The ++ key on every tab · catalog pages push and pop one step at a time"),
        ("44", "The ++ wears its key"),
        ("43", "Keys travel deeper · the +1 gets its moment · swipe actions in full color · custom chrome, corner to corner"),
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
