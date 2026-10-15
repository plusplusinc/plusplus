import Testing
@testable import DesignSystem

@Suite("Row label")
struct RowLabelTests {
    @Test("A detail line joins its parts with dots, each part kept whole")
    func joined() {
        let text = RowLabel.detailText(
            ["Dumbbells, bench", "3 × 10 reps per side", "50 lb"],
            stacked: false,
        )
        // Only the space after each dot can break.
        #expect(text?.replacingOccurrences(of: "\u{00A0}", with: "_")
            == "Dumbbells,_bench_· 3_×_10_reps_per_side_· 50_lb")
        #expect(RowLabel.detailText(["60 s per side"], stacked: false)
            == "60\u{00A0}s\u{00A0}per\u{00A0}side")
    }

    @Test("Stacked, at the accessibility sizes, a part to a line with no dots")
    func stacked() {
        #expect(RowLabel.detailText(["Barbell, bench", "5 × 5 reps", "135 lb"], stacked: true)
            == "Barbell, bench\n5 × 5 reps\n135 lb")
    }

    @Test("No parts, no line")
    func empty() {
        #expect(RowLabel.detailText([], stacked: false) == nil)
        #expect(RowLabel.detailText([], stacked: true) == nil)
    }
}
