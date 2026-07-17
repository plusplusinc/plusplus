import SwiftUI
import SwiftData
import PlusPlusKit

/// The "Tracks" config sheet (2026-07-17, sheet-per-configurable):
/// which metrics exercises on this gear typically track. Toggling
/// writes the equipment's suggested profile; new exercises with the
/// gear start from it. Built-ins are editable too — an explicit
/// override rides `metricsData` (and exports, like any configured
/// built-in); the reset row returns to the catalog's curated profile
/// (the #136 revert precedent). An emptied set on a custom clears the
/// declaration: back to "plain strength gear". A built-in keeps its
/// last chip (emptying would fall back to the catalog set mid-touch);
/// reset is its one path back.
struct EquipmentMetricsSheet: View {
    @Bindable var equipment: Equipment
    @Environment(\.dismiss) private var dismiss

    private var hasOverride: Bool {
        equipment.isBuiltIn && equipment.metricsData != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("TRACKS")
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .kerning(0.7)
                    .foregroundStyle(Theme.textSecondary)
                Text("What exercises on this gear typically track. New exercises with it start from this set. Leave everything off for plain strength gear.")
                    .font(.system(.subheadline))
                    .foregroundStyle(Theme.textSecondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 7)], spacing: 7) {
                ForEach(WorkoutMetric.allCases.filter { !$0.isBlockConfiguration }) { metric in
                    metricChip(metric)
                }
            }

            if hasOverride {
                QuietKey(label: "reset to catalog default", identifier: "resetMetricsButton") {
                    equipment.metricsData = nil
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .background(Theme.background)
    }

    /// Selection blue like every selected state (#210).
    private func metricChip(_ metric: WorkoutMetric) -> some View {
        let profile = equipment.suggestedProfile
        let selected = profile?.contains(metric) == true
        return Button {
            var metrics = profile?.metrics ?? []
            if let index = metrics.firstIndex(of: metric) {
                // A BUILT-IN can't empty its set by toggling: nil falls
                // back to the catalog profile, so the last removal would
                // re-light every curated chip under the user's finger
                // (reviewer catch). The reset row is the one path back
                // to catalog; the last chip stays put.
                if equipment.isBuiltIn && metrics.count == 1 { return }
                metrics.remove(at: index)
            } else {
                metrics.append(metric)
            }
            equipment.suggestedProfile = metrics.isEmpty
                ? nil
                : MetricProfile(metrics, distanceUnit: profile?.distanceUnit ?? .meters)
        } label: {
            Text(metric.label)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(selected ? Theme.onSelected : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(selected ? Theme.selected : Theme.background, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("equipmentMetricChip-\(metric.rawValue)")
        .animation(Theme.Anim.selection, value: selected)
    }
}
