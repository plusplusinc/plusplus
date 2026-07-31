import SwiftUI
import PlusPlusKit

/// One line of the ledger: an exercise on a multi-exercise routine, or a
/// single metric when the routine has one exercise and its metrics are what
/// vary.
struct DiffLedgerRow: Identifiable {
    let id: String
    let label: String
    let target: [PrescriptionRun]
    let prev: [PrescriptionRun]
    let changed: Set<RoutineDiff.Field>
    /// Which way each moved field moved (2026-07-30): `.up` inks the target
    /// token green, `.down` the gentle brick. A changed neutral setting is
    /// in `changed` but absent here and stays plain bright.
    var directions: [RoutineDiff.Field: RoutineDiff.Direction] = [:]
    /// Added since the last run, so there is nothing to compare against.
    /// Distinct from an empty `prev` for any other reason — the row states
    /// it in words to assistive tech rather than announcing silence.
    var isNew: Bool = false
}

/// Today's pending card states what it is asking for beside what happened
/// last time, and prints no delta at all.
///
/// The card used to collapse a routine into one signed number, which on a
/// run read as a value rather than a difference: a `−3:42 /mi` that was
/// really the gap between a static pace target and the last run, painted in
/// progress green before the workout started (Dave's build-126 report,
/// #453). Two columns make the arithmetic the reader's, so a signed number
/// is unrepresentable and the misread cannot recur.
///
/// The `target` column dims what held and marks what moved — since
/// 2026-07-30 with DIRECTION: an ask above the printed prev in the data
/// green, an ask below it in the gentle brick (`Theme.increaseInk`/
/// `decreaseInk`; Dave: "decrease is not a problem"). That supersedes this
/// card's earlier "nothing here is green" — the #453 misread this table
/// replaced was a signed NUMBER wearing progress green before the workout
/// started, and no number here is signed: color rides a token printed
/// beside the prev it differs from, so it can only read as the comparison.
/// `prev` stays one flat brightness throughout, because it is the thing
/// being compared against rather than the thing being read.
struct DiffLedger: View {
    let rows: [DiffLedgerRow]
    /// What the LEFT column is. A plan states what it will ask for, so it
    /// says "target"; a finished workout states what happened, so it says
    /// "did". The table is the same either way, which is the point — two
    /// columns and no delta, so the arithmetic stays the reader's whether
    /// you are reading forwards or back.
    var leadingTitle: String = "target"
    /// Rows shown before the rest go behind a key. Four is roughly where the
    /// card stops being scannable.
    var cap: Int = 4
    @Binding var expanded: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Column { case target, prev }

    private var visible: [DiffLedgerRow] {
        expanded ? rows : Array(rows.prefix(cap))
    }

    private var hidden: Int { max(0, rows.count - cap) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Three mono columns cannot hold at accessibility sizes, so the
            // table reflows to stacked rows rather than truncating — #164's
            // "reflow, don't cap" applied to a table.
            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                grid
            }

            if hidden > 0 {
                QuietKey(
                    // "changes", not "diffs": the working path speaks plain
                    // training English, and the git layer is a second
                    // reading the app never leans on (copy-reviewer).
                    label: expanded ? "show fewer" : "\(hidden) more \(hidden == 1 ? "change" : "changes")",
                    systemImage: expanded ? "chevron.up" : "chevron.down",
                    identifier: "ledgerExpandButton"
                ) {
                    withAnimation(Theme.Anim.standard) { expanded.toggle() }
                }
            }
        }
    }

    // MARK: - Shapes

    private var grid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 3) {
            GridRow {
                Color.clear.frame(height: 0).gridColumnAlignment(.leading)
                columnHeader(leadingTitle).gridColumnAlignment(.trailing)
                columnHeader("prev").gridColumnAlignment(.trailing)
            }
            ForEach(visible) { row in
                // A modifier on a GridRow applies to each of its CELLS, not
                // to the row — so the whole sentence rides the label cell and
                // the value cells are hidden, rather than every row
                // announcing itself three times over.
                GridRow {
                    rowLabel(row.label)
                        .accessibilityLabel(spoken(row))
                    cell(row.target, changed: row.changed, directions: row.directions, column: .target, lineLimit: 1)
                        .accessibilityHidden(true)
                    cell(row.prev, changed: row.changed, directions: row.directions, column: .prev, lineLimit: 1)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(visible) { row in
                VStack(alignment: .leading, spacing: 3) {
                    rowLabel(row.label)
                    stackedLine(leadingTitle, runs: row.target, changed: row.changed, directions: row.directions, column: .target)
                    stackedLine("prev", runs: row.prev, changed: row.changed, directions: row.directions, column: .prev)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(row))
            }
        }
    }

    private func stackedLine(_ title: String, runs: [PrescriptionRun], changed: Set<RoutineDiff.Field>, directions: [RoutineDiff.Field: RoutineDiff.Direction], column: Column) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            columnHeader(title)
            cell(runs, changed: changed, directions: directions, column: column, lineLimit: nil)
        }
    }

    // MARK: - Parts

    /// The row's key. It WRAPS rather than truncating (Dave, 2026-07-27),
    /// departing from the rail's "names stay single-line" rule on purpose:
    /// here the name says which of five exercises the two numbers beside it
    /// belong to, so a clipped name makes the row unreadable rather than
    /// merely abbreviated.
    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Hidden from assistive tech: each row carries the whole comparison in
    /// its own label, so a floating "target" would announce with no subject
    /// (the BlockBar rule, 2026-07-23).
    private func columnHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Theme.textFaint)
            .accessibilityHidden(true)
    }

    /// Runs concatenate into ONE `Text` so the cell truncates gracefully and
    /// each run keeps its own ink — the idiom the diff summary line used
    /// before this replaced it.
    private func cell(_ runs: [PrescriptionRun], changed: Set<RoutineDiff.Field>, directions: [RoutineDiff.Field: RoutineDiff.Direction], column: Column, lineLimit: Int?) -> some View {
        // A missing side is a placeholder glyph, never a blank: an empty
        // cell reads as a rendering fault rather than as "nothing to
        // compare".
        let body = runs.isEmpty
            ? Text("—").foregroundStyle(Theme.textFaint)
            : runs.reduce(Text("")) { result, run in
                result + Text(run.text).foregroundStyle(ink(run, changed: changed, directions: directions, column: column))
            }
        return body
            .font(.system(.caption, design: .monospaced))
            .monospacedDigit()
            .lineLimit(lineLimit)
            // Between xLarge and the accessibility sizes there is no reflow,
            // and a truncated number in a comparison is a WRONG number —
            // the exact failure this table exists to end.
            .minimumScaleFactor(0.7)
    }

    private func ink(_ run: PrescriptionRun, changed: Set<RoutineDiff.Field>, directions: [RoutineDiff.Field: RoutineDiff.Direction], column: Column) -> Color {
        // prev is reference material: one brightness, no emphasis inside it,
        // so the only thing that varies anywhere in the table is the token
        // that moved in today's column.
        //
        // ⚠️ Kept in step with `ExerciseRailRow.ink` by hand — the two
        // surfaces print the same producer's rows and must agree on what a
        // moved token wears.
        guard column == .target else { return Theme.textFaint }
        guard let field = run.field, changed.contains(field) else { return Theme.textSecondary }
        return switch directions[field] {
        case .up: Theme.increaseInk
        case .down: Theme.decreaseInk
        // A changed neutral setting (resistance, incline…): moved, but
        // neither progress nor regress — plain bright.
        case nil: Theme.textPrimary
        }
    }

    /// The raw cell reads badly aloud ("three times eight at one three five
    /// l b"), so a row announces as one sentence with spoken separators.
    private func spoken(_ row: DiffLedgerRow) -> String {
        func phrase(_ runs: [PrescriptionRun]) -> String {
            runs.map { run -> String in
                switch run.text {
                case "×", "× ": return " by "
                case " @ ": return " at "
                default: return run.text
                }
            }.joined()
        }
        let target = phrase(row.target)
        let prev = phrase(row.prev)
        // Keyed on the row's own flag, not on an empty column: a blank prev
        // can also mean this one metric is missing from an exercise that was
        // very much done, and announcing "not done before" there is false.
        let lead = leadingTitle.sentenceCasedFirst
        if row.isNew { return "\(row.label). \(lead) \(target). Not done before." }
        guard !prev.isEmpty else { return "\(row.label). \(lead) \(target)." }
        return "\(row.label). \(lead) \(target). Previously \(prev)."
    }
}
