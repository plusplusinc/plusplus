import Foundation

/// One compact line of metric values ("10 reps @ 135 lb", "2000 m · 7:52 ·
/// lvl 5") — the shared vocabulary for target descriptions, up-next lines,
/// history rows, and the watch. Pure formatting over a profile and a value
/// lookup, so every surface renders the same set the same way.
public enum MetricSummary {
    /// Values joined " · " in canonical order. The classic rep-and-load
    /// pair keeps its idiomatic shape ("10 reps @ 135 lb" — assistance
    /// reads "10 reps @ 60 lb assist"); everything else is the metric's
    /// own display text. `repsText` overrides the reps number so target
    /// ranges ("8–10") survive where a plain Double can't carry them.
    /// Nil when nothing has a value.
    public static func line(
        profile: MetricProfile,
        weightUnit: WeightUnit = .lb,
        repsText: String? = nil,
        value: (WorkoutMetric) -> Double?
    ) -> String? {
        var parts: [String] = []
        var repsPart: String?
        var loadPart: String?

        for metric in profile.metrics {
            switch metric {
            case .reps:
                if let repsText {
                    repsPart = "\(repsText) reps"
                } else if let reps = value(.reps) {
                    repsPart = "\(WorkoutMetric.reps.formatted(reps)) reps"
                }
            case .weight:
                if let weight = value(.weight), weight > 0 {
                    loadPart = WorkoutMetric.weight.displayText(weight, weightUnit: weightUnit)
                }
            case .assistance:
                if let assist = value(.assistance), assist > 0 {
                    loadPart = WorkoutMetric.assistance.displayText(assist, weightUnit: weightUnit) + " assist"
                }
            default:
                if let raw = value(metric) {
                    parts.append(metric.displayText(raw, weightUnit: weightUnit, distanceUnit: profile.distanceUnit))
                }
            }
        }

        // Reps and load fuse into the classic pair, and lead the line.
        let lead: String?
        switch (repsPart, loadPart) {
        case (let reps?, let load?): lead = "\(reps) @ \(load)"
        case (let reps?, nil): lead = reps
        case (nil, let load?): lead = load
        case (nil, nil): lead = nil
        }
        let all = (lead.map { [$0] } ?? []) + parts
        return all.isEmpty ? nil : all.joined(separator: " · ")
    }
}
