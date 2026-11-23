import CoreGraphics
import Testing
@testable import DesignSystem

/// Where a workout row's bar segments and the muscle words under them go.
@Suite("Segmented bar")
struct SegmentedBarTests {
    @Test("Segments fill the bar's share of the column, in order, gaps between")
    func fills() throws {
        let frames = SegmentedBar.frames(shares: [0.6, 0.4], fill: 0.5, in: 200)
        let last = try #require(frames.last)
        #expect(last.upperBound == 100)
        #expect(frames[1].lowerBound - frames[0].upperBound == SegmentedBar.gap)
        #expect(frames[0].upperBound - frames[0].lowerBound > frames[1].upperBound - frames[1]
            .lowerBound)
    }

    @Test("No segment is narrower than the minimum, and a full bar ends at the column's end")
    func bounds() throws {
        let tiny = SegmentedBar.frames(shares: [0.9, 0.05, 0.05], fill: 0.01, in: 200)
        for frame in tiny {
            #expect(frame.upperBound - frame.lowerBound >= SegmentedBar.minSegment - 1e-9)
        }
        let full = SegmentedBar.frames(shares: [0.5, 0.5], fill: 1, in: 200)
        #expect(try #require(full.last).upperBound == 200)
    }

    @Test("Each word starts at its segment, or just after the word before; none overlap")
    func words() {
        let starts: [CGFloat] = [0, 20, 40]
        for widths: [CGFloat] in [[10, 10, 10], [50, 30, 400], [300, 5, 5]] {
            let origins = WordPlacement.origins(starts: starts, widths: widths, gap: 8)
            for index in origins.indices {
                #expect(origins[index] >= starts[index])
                if index > 0 {
                    #expect(origins[index] >= origins[index - 1] + widths[index - 1] + 8)
                }
            }
        }
        #expect(WordPlacement.origins(starts: starts, widths: [10, 10, 10], gap: 8) == starts)
    }
}
