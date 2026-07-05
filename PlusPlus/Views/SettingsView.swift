import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PlusPlusKit

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: AppAppearance = .dark
    @Environment(\.modelContext) private var modelContext

    @State private var showingExporter = false
    @State private var exportDocument: InterchangeDocument?
    @State private var showingImporter = false
    @State private var importResultMessage: String?
    @State private var dataError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.displayName)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button("Export Data…") {
                        prepareExport()
                    }
                    Button("Import Data…") {
                        showingImporter = true
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Exports your exercises, workouts, and history as a JSON file (interchange schema v1). Import merges: exercises and workouts by name, history append-only.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
        .preferredColorScheme(appearance.colorScheme)
        .onAppear {
            UISegmentedControl.appearance().setTitleTextAttributes(
                [.font: UIFont.systemFont(ofSize: 15, weight: .medium)],
                for: .normal
            )
        }
    }

    private func prepareExport() {
        do {
            let bundle = try InterchangeMapping.exportBundle(context: modelContext)
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
