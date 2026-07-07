import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PlusPlusKit

/// Settings, v2 (#67): sync first, then units and data. The SYNC section
/// is the #23 shape with the wiring pending — the connect button explains
/// itself instead of doing nothing silently.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw: String = AppAppearance.system.rawValue
    @Environment(\.modelContext) private var modelContext

    @State private var showingExporter = false
    @State private var exportDocument: InterchangeDocument?
    @State private var showingImporter = false
    @State private var importResultMessage: String?
    @State private var dataError: String?
    @State private var showingSyncExplainer = false
    @State private var showingEquipmentSetup = false
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Settings", action: { dismiss() })
                .padding(.horizontal, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SheetSectionLabel("SYNC")
                        .padding(.top, 16)

                    Button {
                        showingSyncExplainer = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(.footnote))
                            Text("Connect GitHub")
                                .font(.system(.subheadline, weight: .bold))
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong))
                    }
                    Text("Your program and history live as JSON in a repo you own.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 6)

                    SheetSectionLabel("APPEARANCE")
                        .padding(.top, 16)
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
                        .padding(.top, 16)
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

                    SheetSectionLabel("EQUIPMENT ACCESS")
                        .padding(.top, 16)
                    Button {
                        showingEquipmentSetup = true
                    } label: {
                        HStack {
                            Text("Re-run setup")
                                .font(.system(.footnote))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(equipmentSummary)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                    }
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
                    .accessibilityIdentifier("equipmentSetupButton")
                    Text("filters the exercise catalog everywhere · never touches logged history")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 6)

                    SheetSectionLabel("DATA")
                        .padding(.top, 16)
                    VStack(spacing: 0) {
                        Button {
                            prepareExport()
                        } label: {
                            Text("Export data…")
                                .font(.system(.footnote))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                        }
                        Divider().overlay(Theme.border)
                        Button {
                            showingImporter = true
                        } label: {
                            Text("Import data…")
                                .font(.system(.footnote))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                        }
                    }
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))

                    Text("Interchange schema v\(Interchange.schemaVersion) — exercises + workouts + history as JSON, ready for the workouts repo.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .presentationBackground(Theme.surface)
        .fullScreenCover(isPresented: $showingEquipmentSetup) {
            OnboardingView(isRerun: true)
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
        .alert("GitHub Sync", isPresented: $showingSyncExplainer) {
            Button("OK") {}
        } message: {
            Text("Coming soon: the sync engine is built and tested; connecting your account lands with the GitHub App setup (issue #23). Until then, Export/Import moves data through the same format.")
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

    private var equipmentSummary: String {
        let owned = allEquipment.filter { $0.isBuiltIn && $0.inLibrary }.count
        return owned == 0 ? "bodyweight only" : "\(owned) item\(owned == 1 ? "" : "s")"
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
        if summary.workoutsCreated + summary.workoutsReplaced > 0 {
            lines.append("Workouts: \(summary.workoutsCreated) added, \(summary.workoutsReplaced) replaced")
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
