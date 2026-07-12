import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PlusPlusKit

/// Settings, v4 §B: a pushed page off Today, ordered by daily use —
/// APPEARANCE · UNITS · EQUIPMENT · DATA · HOME SCREEN & SIRI · SYNC. Sync dropped from first
/// position: it's aspirational until #23 ships, and it shouldn't
/// headline the page you open to flip dark mode. One footer caption per
/// section max, only where semantics surprise (§G).
struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw: String = AppAppearance.system.rawValue
    @Environment(\.modelContext) private var modelContext

    @State private var showingExporter = false
    @State private var exportDocument: InterchangeDocument?
    @State private var showingImporter = false
    @State private var importResultMessage: String?
    @State private var dataError: String?
    @State private var showingSync = false
    @State private var sync = GitHubSyncCoordinator.shared
    @State private var showingEquipmentSetup = false
    @State private var showingLibraryTray = false
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SheetSectionLabel("APPEARANCE")
                        .padding(.top, 24)
                    SegmentedTabs(
                        options: AppAppearance.allCases.map(\.label),
                        selectedIndex: Binding(
                            get: {
                                AppAppearance.allCases.firstIndex(of: AppAppearance(rawValue: appearanceRaw) ?? .system) ?? 0
                            },
                            set: { appearanceRaw = AppAppearance.allCases[$0].rawValue }
                        )
                    )

                    SheetSectionLabel("UNITS")
                        .padding(.top, 24)
                    SegmentedTabs(
                        options: ["lb", "kg"],
                        selectedIndex: Binding(
                            get: { weightUnitRaw == WeightUnit.kg.rawValue ? 1 : 0 },
                            set: { weightUnitRaw = ($0 == 1 ? WeightUnit.kg : WeightUnit.lb).rawValue }
                        )
                    )
                    Text("Changes labels and stepping only — logged numbers are never converted.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 6)

                    SheetSectionLabel("EQUIPMENT")
                        .padding(.top, 24)
                    // Nav rows are secondary raised keys (Quiet Arcade:
                    // navigation is a press). "My equipment" curates the
                    // active library; the summary reflects it by name so
                    // the app-wide scope is legible here too.
                    Button {
                        showingEquipmentSetup = true
                    } label: {
                        HStack {
                            Text("My equipment")
                                .font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(equipmentSummary)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(.caption, weight: .bold))
                                .foregroundStyle(Theme.textFaint)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong))
                    }
                    .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
                    .accessibilityIdentifier("equipmentSetupButton")
                    // The switcher is discoverable here too, but the
                    // control's home is the Equipment tab (where the list
                    // re-renders live). Present only once it's meaningful.
                    if libraries.count > 1 {
                        Button {
                            showingLibraryTray = true
                        } label: {
                            HStack {
                                Text("Switch library")
                                    .font(.system(.footnote, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(.caption, weight: .bold))
                                    .foregroundStyle(Theme.textFaint)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong))
                        }
                        .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
                        .accessibilityIdentifier("switchLibraryButton")
                        .padding(.top, 8)
                    }
                    Text("Switching libraries changes what counts as your gear everywhere. Never touches logged history.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 6)

                    SheetSectionLabel("DATA")
                        .padding(.top, 24)
                    // Two separate keys, not one container: each is its
                    // own commit.
                    Button {
                        prepareExport()
                    } label: {
                        HStack {
                            Text("Export data…")
                                .font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("json")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.textFaint)
                            Image(systemName: "arrow.up.right")
                                .font(.system(.caption, weight: .bold))
                                .foregroundStyle(Theme.textFaint)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong))
                    }
                    .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
                    Button {
                        showingImporter = true
                    } label: {
                        HStack {
                            Text("Import data…")
                                .font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(.caption, weight: .bold))
                                .foregroundStyle(Theme.textFaint)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong))
                    }
                    .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
                    .padding(.top, 8)

                    Text("Interchange schema v\(Interchange.schemaVersion) — exercises + routines + history as JSON.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 6)

                    // The one place widgets/Siri can be discovered
                    // (#246): they're the app's only pull-back-in
                    // surface, and nothing else ever names them — a
                    // widget can't communicate by presence before it's
                    // installed. Facts in captions, nothing tappable:
                    // installation lives on the home screen.
                    SheetSectionLabel("HOME SCREEN & SIRI")
                        .padding(.top, 24)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Two widgets ship with the app: Today (your schedule at a glance) and Streak (a 12-week row). Long-press the home screen \u{2192} Edit \u{2192} Add Widget \u{2192} PlusPlus.")
                            .font(.system(.footnote))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Siri knows \u{201C}Start a routine in PlusPlus\u{201D} and \u{201C}What's today in PlusPlus\u{201D}.")
                            .font(.system(.footnote))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))

                    // Health access, re-runnable like equipment setup:
                    // the welcome flow asks once, this row is for
                    // everyone who said "not now" (the sheet only
                    // appears while something is still undecided —
                    // afterwards access lives in iOS Settings).
                    SheetSectionLabel("APPLE HEALTH")
                        .padding(.top, 24)
                    Button {
                        HealthAccess.requestEverything()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .font(.system(.footnote))
                            Text("Connect Apple Health")
                                .font(.system(.subheadline, weight: .bold))
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong))
                    }
                    .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
                    .accessibilityIdentifier("connectHealthButton")
                    Text("Heart rate shows live during workouts and on every record; finished workouts save to Health. Manage access anytime in iOS Settings \u{2192} Privacy \u{2192} Health.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 6)

                    SheetSectionLabel("SYNC")
                        .padding(.top, 24)
                    Button {
                        showingSync = true
                    } label: {
                        HStack(spacing: 8) {
                            Image("GitHubMark")
                                .resizable().scaledToFit().frame(width: 15, height: 15)
                            Text(syncRowTitle)
                                .font(.system(.subheadline, weight: .bold))
                            Spacer()
                            // Green = connected, red = not (a connection status,
                            // the one place we override the purple "done" mark).
                            switch sync.connection {
                            case .connected:
                                Circle().fill(Theme.accent).frame(width: 8, height: 8)
                            case .disconnected:
                                Circle().fill(Theme.destructive).frame(width: 8, height: 8)
                            case .unconfigured:
                                EmptyView()
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(.caption, weight: .bold))
                                .foregroundStyle(Theme.textFaint)
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong))
                    }
                    .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
                    .accessibilityIdentifier("syncRow")
                    Text("Your program and history live as JSON in a repo you own.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 6)

                    // Quiet version info, no section (SSB).
                    Text("++ build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev")")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                }
                .padding(.bottom, 30)
            }
        }
        .padding(.horizontal, 16)
        .background(Theme.background)
        .pushedScreenChrome(title: "Settings", onBack: { dismiss() })
        .navigationDestination(isPresented: $showingEquipmentSetup) {
            CatalogBrowseScreen(kind: .equipment, setupMode: true)
        }
        .sheet(isPresented: $showingLibraryTray) {
            EquipmentLibraryTray()
        }
        .navigationDestination(isPresented: $showingSync) {
            GitHubConnectScreen()
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "plusplus-export"
        ) { result in
            if case .failure(let error) = result {
                dataError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json]
        ) { result in
            handleImport(result)
        }
        .alert("Import Complete", isPresented: Binding(
            get: { importResultMessage != nil },
            set: { if !$0 { importResultMessage = nil } }
        )) {
            Button("OK") { importResultMessage = nil }
        } message: {
            Text(importResultMessage ?? "")
        }
        .alert("Something Went Wrong", isPresented: Binding(
            get: { dataError != nil },
            set: { if !$0 { dataError = nil } }
        )) {
            Button("OK") { dataError = nil }
        } message: {
            Text(dataError ?? "")
        }
    }

    private var syncRowTitle: String {
        sync.isConnected ? "GitHub" : "Connect GitHub"
    }

    private var equipmentSummary: String {
        let active = EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
        let count = active?.members.count ?? 0
        let items = count == 0 ? "bodyweight only" : "\(count) item\(count == 1 ? "" : "s")"
        // Name the library once more than one exists ("Home · 6 items").
        if libraries.count > 1, let name = active?.name {
            return "\(name) · \(items)"
        }
        return items
    }

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
            // A bundle that declares units is authoritative for its own
            // numbers — adopt its setting so they keep meaning what they say.
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

/// Minimal FileDocument wrapper so fileExporter can hand off encoded
/// interchange data.
struct InterchangeDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
