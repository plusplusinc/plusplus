import SwiftUI
import SwiftData

/// The equipment-library switcher (medium-detent tray, Dave's call):
/// one row per library, tap to switch — the surface behind visibly
/// re-renders in the same instant, which is what makes the app-wide
/// scope legible. Rename/Delete live in a per-row … menu (#241:
/// destructive actions live in ellipsis menus); Delete hides on the
/// last library so a store can never reach zero. Creation lands on an
/// EMPTY library by design: the value is a curated short list of what
/// you'd use there, so there is deliberately no "copy" or "add all".
struct EquipmentLibraryTray: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    @State private var promptingNew = false
    @State private var newName = ""
    @State private var renaming: EquipmentLibrary?
    @State private var renameText = ""
    @State private var deleting: EquipmentLibrary?

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Equipment libraries", closeOnly: true, action: { dismiss() })

            Text("One list per place you train. Switching changes what counts as your gear everywhere.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 6)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(libraries.enumerated()), id: \.element.persistentModelID) { index, library in
                        libraryRow(library)
                        if index < libraries.count - 1 {
                            Divider().overlay(Theme.border)
                        }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
                .padding(.top, 14)
                // ONE feedback for the switch, above the ForEach: on the
                // row it fired once per rendered library (swift-reviewer).
                .sensoryFeedback(.selection, trigger: activeLibraryID)

                // Creation is green (#202); starts empty and active, so
                // the tab's browse-the-catalog empty state takes over.
                Button {
                    newName = ""
                    promptingNew = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(.caption, weight: .semibold))
                        Text("New library…")
                            .font(.system(.footnote, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 48)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .strokeBorder(Theme.borderStrong)
                    )
                }
                .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
                .accessibilityIdentifier("newLibraryButton")
                .padding(.top, 10)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .presentationBackground(Theme.background)
        .presentationDetents([.medium, .large])
        .alert("New library", isPresented: $promptingNew) {
            TextField("Hotel, Garage, Office…", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { createLibrary() }
        } message: {
            Text("Starts empty. Pick its gear from the catalog.")
        }
        .alert("Rename library", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") { renameLibrary() }
        }
        .confirmationDialog(
            "Delete \u{201C}\(deleting?.name ?? "")\u{201D}?",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete library", role: .destructive) { deleteLibrary() }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("The gear itself stays in the catalog and in your other libraries.")
        }
    }

    // MARK: - Rows

    private func libraryRow(_ library: EquipmentLibrary) -> some View {
        HStack(spacing: 8) {
            // Activation is the row; management is the … menu beside it.
            Button {
                activeLibraryID = library.uuid.uuidString
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: library === activeLibrary ? "checkmark.circle.fill" : "circle")
                        .font(.system(.footnote))
                        .foregroundStyle(library === activeLibrary ? Theme.selected : Theme.textFaint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(library.name)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        gearChips(library)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("libraryRow-\(library.name)")

            Menu {
                Button("Rename…") {
                    renameText = library.name
                    renaming = library
                }
                if libraries.count > 1 {
                    Button("Delete…", role: .destructive) {
                        deleting = library
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(library.name) options")
            .accessibilityIdentifier("libraryMenu-\(library.name)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// The library's gear as chips — as many as the row fits, then a
    /// "+n" for the rest (Dave: show what fits, not a bare count).
    /// Alphabetical so the same library always reads the same. An empty
    /// library is a feature (bodyweight-only travel), not a blank.
    private func gearChips(_ library: EquipmentLibrary) -> some View {
        let names = library.members.map(\.name).sorted()
        return Group {
            if names.isEmpty {
                Text("bodyweight only")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
            } else {
                ViewThatFits(in: .horizontal) {
                    chipLine(names, showing: names.count)
                    chipLine(names, showing: 4)
                    chipLine(names, showing: 3)
                    chipLine(names, showing: 2)
                    chipLine(names, showing: 1)
                    chipLine(names, showing: 0)
                }
            }
        }
    }

    private func chipLine(_ names: [String], showing: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(names.prefix(showing), id: \.self) { name in
                gearChip(name)
            }
            if names.count > showing {
                gearChip("+\(names.count - showing)")
            }
        }
    }

    private func gearChip(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Theme.border))
    }

    // MARK: - Actions

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
        dismiss()
    }

    private func renameLibrary() {
        defer { renaming = nil }
        guard let library = renaming else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !libraries.contains(where: { $0 !== library && $0.name.lowercased() == trimmed.lowercased() })
        else { return }
        library.name = trimmed
    }

    private func deleteLibrary() {
        defer { deleting = nil }
        guard let library = deleting, libraries.count > 1 else { return }
        let wasActive = library === activeLibrary
        modelContext.delete(library)
        // `order` isn't reindexed after a delete: it drives sort STABILITY
        // only (not contiguity), and creation uses max()+1, so a gap can't
        // collide. Reindexing would be churn for no behavior change.
        if wasActive, let next = libraries.first(where: { $0 !== library }) {
            activeLibraryID = next.uuid.uuidString
        }
    }
}
