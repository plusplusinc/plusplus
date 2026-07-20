import SwiftUI
import SwiftData

/// The routine catalog's Kit filter sheet (Dave, 2026-07-20). One radio list
/// that both SWITCHES the kit the catalog judges against (app-wide, like the
/// Equipment-tab switcher) and picks the fit mode: a kit (only what it can
/// do), No equipment (bodyweight only), or All routines (drop the lens).
/// Selecting any row applies and closes. Kit management (new/rename/delete)
/// stays on the Equipment tab — this sheet only switches + filters.
struct RoutineKitFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""
    @Binding var mode: RoutineCatalogScreen.GearFit?

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Kit", closeOnly: true, action: { dismiss() })

            Text("Browse against a kit, or drop the lens. Switching a kit changes what counts as your gear everywhere.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 6)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(libraries.enumerated()), id: \.element.persistentModelID) { _, library in
                        kitRow(library)
                        Divider().overlay(Theme.border)
                    }
                    modeRow(
                        symbol: "figure.strengthtraining.functional",
                        title: "No equipment",
                        subtitle: "only routines that need no gear",
                        selected: mode == .bodyweightOnly
                    ) { apply(.bodyweightOnly) }
                    Divider().overlay(Theme.border)
                    modeRow(
                        symbol: "square.stack.3d.up",
                        title: "All routines",
                        subtitle: "every routine, whatever your kit",
                        selected: mode == nil
                    ) { apply(nil) }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
                .padding(.top, 14)
                // ONE feedback for the applied change, not once per row.
                .sensoryFeedback(.selection, trigger: activeLibraryID)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .presentationBackground(Theme.background)
        .presentationDetents([.medium, .large])
    }

    // MARK: - Rows

    private func kitRow(_ library: EquipmentLibrary) -> some View {
        let selected = mode == .mine && library === activeLibrary
        return Button {
            activeLibraryID = library.uuid.uuidString
            apply(.mine)
        } label: {
            rowContent(
                selected: selected,
                symbol: "dumbbell.fill",
                title: library.name,
                subtitle: gearSummary(library)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("kitFilterRow-\(library.name)")
    }

    private func modeRow(
        symbol: String,
        title: String,
        subtitle: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            rowContent(selected: selected, symbol: symbol, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    private func rowContent(selected: Bool, symbol: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(.footnote))
                .foregroundStyle(selected ? Theme.selected : Theme.textFaint)
            Image(systemName: symbol)
                .font(.system(.footnote))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func gearSummary(_ library: EquipmentLibrary) -> String {
        let names = library.members.map(\.name).sorted()
        return names.isEmpty ? "bodyweight only" : names.joined(separator: " · ")
    }

    private func apply(_ newMode: RoutineCatalogScreen.GearFit?) {
        mode = newMode
        dismiss()
    }
}
