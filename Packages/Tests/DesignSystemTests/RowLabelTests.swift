import Testing
@testable import DesignSystem

@Suite("Row label")
struct RowLabelTests {
    @Test("A detail line joins its parts with dots, each part kept whole")
    func joined() {
        let text = RowLabel.detailText(
            ["3 × 10 reps per side", "20 lb/side"],
            stacked: false,
        )
        // Only the space after each dot can break.
        #expect(text?.replacingOccurrences(of: "\u{00A0}", with: "_")
            == "3_×_10_reps_per_side_· 20_lb/side")
        #expect(RowLabel.detailText(["60 s per side"], stacked: false)
            == "60\u{00A0}s\u{00A0}per\u{00A0}side")
    }

    @Test("Stacked, at the accessibility sizes, a part to a line with no dots")
    func stacked() {
        #expect(RowLabel.detailText(["5 × 5 reps", "135 lb"], stacked: true)
            == "5 × 5 reps\n135 lb")
    }

    @Test("No parts, no line")
    func empty() {
        #expect(RowLabel.detailText([], stacked: false) == nil)
        #expect(RowLabel.detailText([], stacked: true) == nil)
    }
}
