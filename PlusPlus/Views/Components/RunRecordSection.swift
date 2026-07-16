import SwiftUI
import MapKit
import Charts
import PlusPlusKit

/// The run half of a session record (#378): route map, headline stats,
/// splits. Mounted by `SessionDetailView` only when the session carries a
/// run — indoor records render pixel-identical without it. Read-only v1:
/// the map doesn't pan, the chart doesn't scrub.
///
/// Grammar: the route strokes `Theme.accent` (a recorded route is data —
/// green, never chrome); splits render in neutral ink with NO fast/slow
/// coloring and no per-split deltas (anti-shame: a slow mile is a fact,
/// not a warning).
struct RunRecordSection: View {
    let session: WorkoutSession

    /// Parsed off-main in `.task` — a long run's sidecar is ~1 MB of XML
    /// and must not stutter the push. The stat line renders from the
    /// denormalized columns immediately (and even when the sidecar never
    /// restored, or a future watch-born summary has no route at all).
    @State private var track: RouteTrack?

    /// The unit splits and pace quote against: the first outdoor set's
    /// snapshot unit (decoded profiles only — the reconstructed-profile
    /// law), else any distance/pace-tracking set's unit (a foreign
    /// sidecar paired onto a session whose sets never carried the outdoor
    /// flag), falling back to miles.
    private var runUnit: DistanceUnit {
        let profiles = session.sortedSetLogs.compactMap { MetricProfile.decode(from: $0.metricsData) }
        return profiles.first(where: \.isOutdoor)?.distanceUnit
            ?? profiles.first { $0.contains(.distance) || $0.contains(.pace) }?.distanceUnit
            ?? .miles
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let track, !track.isEmpty {
                routeMap(track)
            }
            // A route-only record (foreign sidecar, no summary) has no
            // stats to state — an empty full-width HStack would just be a
            // ghost gap between map and splits.
            if session.runDistanceMeters != nil {
                statLine
            }
            if let track {
                let splits = track.splits(per: runUnit)
                if splits.count >= 2 {
                    splitsChart(splits)
                    splitsTable(splits)
                } else if let only = splits.first {
                    splitsTable([only])
                }
            }
        }
        // Keyed on route presence so a sidecar attached by a background
        // sync WHILE the record is open still gets its map (the id read
        // also registers observation — body otherwise never touches
        // routeData).
        .task(id: session.routeData != nil) {
            guard track == nil, let data = session.routeData else { return }
            let decoded = await Task.detached(priority: .userInitiated) {
                try? GPX.decode(data).track
            }.value
            track = decoded
        }
    }

    // MARK: - Map

    private func routeMap(_ track: RouteTrack) -> some View {
        Map(initialPosition: .region(Self.region(fitting: track)), interactionModes: []) {
            // One polyline per segment: a pause gap renders as a gap,
            // honestly — never a phantom straight line.
            ForEach(Array(track.segments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.border)
        )
        .accessibilityLabel("Route map")
    }

    /// The track's bounding box, padded so the stroke never kisses the
    /// frame. Pure math over quantized fixes — deterministic.
    static func region(fitting track: RouteTrack) -> MKCoordinateRegion {
        let fixes = track.segments.flatMap { $0 }
        guard let first = fixes.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for fix in fixes {
            minLat = min(minLat, fix.latitude); maxLat = max(maxLat, fix.latitude)
            minLon = min(minLon, fix.longitude); maxLon = max(maxLon, fix.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.35, 0.003),
                longitudeDelta: max((maxLon - minLon) * 1.35, 0.003)
            )
        )
    }

    // MARK: - Stats

    /// "3.11 mi · 8:42 /mi · ↗ 46 m" — from the denormalized columns, in
    /// the record's mono caption ink beside the Health facts.
    private var statLine: some View {
        HStack(spacing: 12) {
            if let meters = session.runDistanceMeters {
                Text("\(Image(systemName: "figure.run")) \(WorkoutMetric.distance.displayText(runUnit.value(fromMeters: meters), distanceUnit: runUnit))")
            }
            if let meters = session.runDistanceMeters, let moving = session.runMovingSeconds, meters > 0 {
                let pace = moving / (meters / runUnit.paceReferenceMeters)
                Text("\(Self.paceText(pace)) \(runUnit.paceLabel)")
            }
            if let gain = session.runElevationGainMeters, gain >= 1 {
                Text("\(Image(systemName: "arrow.up.right")) \(Int(gain.rounded())) m")
            }
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Splits

    private func splitsChart(_ splits: [RouteTrack.Split]) -> some View {
        let paces = splits.map(\.paceSeconds)
        let lo = (paces.min() ?? 0) * 0.9
        let hi = (paces.max() ?? 1) * 1.05
        return Chart(splits, id: \.index) { split in
            BarMark(
                x: .value("Split", split.index),
                y: .value("Pace", split.paceSeconds)
            )
            .foregroundStyle(Theme.accent)
            .cornerRadius(3)
        }
        .chartYScale(domain: lo...hi)
        .chartXAxis {
            AxisMarks(values: splits.map(\.index)) { _ in
                AxisValueLabel()
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel {
                    if let pace = value.as(Double.self) {
                        Text(Self.paceText(pace))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                    }
                }
            }
        }
        .frame(height: 120)
    }

    private func splitsTable(_ splits: [RouteTrack.Split]) -> some View {
        VStack(spacing: 4) {
            ForEach(splits, id: \.index) { split in
                HStack {
                    Text(Self.splitLabel(split, unit: runUnit))
                        .foregroundStyle(Theme.textFaint)
                    Spacer()
                    Text(Self.paceText(split.paceSeconds))
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.system(.caption, design: .monospaced))
            }
        }
    }

    /// "MI 3", "KM 5", "500M 4" — or a partial's honest fraction:
    /// "0.4 MI". Neutral ink throughout; no split is scolded.
    static func splitLabel(_ split: RouteTrack.Split, unit: DistanceUnit) -> String {
        let bucket = unit.paceReferenceMeters
        let name: String
        switch unit {
        case .miles: name = "MI"
        case .kilometers: name = "KM"
        case .meters: name = "500M"
        }
        if split.meters >= bucket - 1 {
            return "\(name) \(split.index)"
        }
        // A partial of a 500 m erg bucket reads cleaner as absolute
        // meters ("200M") than as a fraction of the bucket ("0.4 500M").
        if unit == .meters {
            return "\(Int(split.meters.rounded()))M"
        }
        let fraction = split.meters / bucket
        return String(format: "%.1f %@", fraction, name)
    }

    static func paceText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
