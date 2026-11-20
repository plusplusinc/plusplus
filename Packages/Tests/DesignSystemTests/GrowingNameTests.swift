import CoreGraphics
import Testing
@testable import DesignSystem

/// How a name is drawn as it grows from a row's size into the current exercise's, from the font
/// sizes' ratio and the two sizes as laid out. The figures are "Barbell back squat" at the
/// default size, in points: one line both ways, 148 wide at 17 pt and 235 at 28 pt.
@Suite("Growing name")
struct GrowingNameTests {
    private let ratio: CGFloat = 28 / 17
    private let oneLine = GrowingName.Sizes(
        small: CGSize(width: 148, height: 22),
        large: CGSize(width: 235, height: 34),
    )

    /// The font sizes' ratio's scale at `growth`: a row's size at 0, the large name's own at 1.
    private func ratioScale(_ growth: CGFloat) -> CGFloat {
        1 / ratio + (1 - 1 / ratio) * growth
    }

    @Test("Breaking alike, the large name shrinks across into the small name's measured width")
    func shrinksIntoMeasuredWidth() {
        let nearRest = GrowingName.Drawing(growth: 0.0001, ratio: ratio, sizes: oneLine)
        #expect(abs(nearRest.largeScale.width * 235 - 148) < 0.01)
        // Up and down, the font sizes' ratio, so the letters keep their height.
        #expect(abs(nearRest.largeScale.height - 17 / 28) < 0.001)
        #expect(nearRest.largeOpacity == 1)
    }

    @Test("Breaking alike, the scale across runs straight from the measured width's to 1")
    func widthScaleRunsLinearly() {
        let resting: CGFloat = 148 / 235
        for growth: CGFloat in [0.25, 0.5, 0.75] {
            let drawing = GrowingName.Drawing(growth: growth, ratio: ratio, sizes: oneLine)
            #expect(abs(drawing.largeScale.width - (resting + (1 - resting) * growth)) < 0.0001)
            #expect(abs(drawing.largeScale.height - ratioScale(growth)) < 0.0001)
            #expect(drawing.largeOpacity == 1)
        }
        let grown = GrowingName.Drawing(growth: 1, ratio: ratio, sizes: oneLine)
        #expect(grown.largeScale == CGSize(width: 1, height: 1))
        #expect(grown.largeOpacity == 1)
    }

    @Test("At rest the small name shows unscaled, and the large one is hidden and unscaled")
    func atRest() {
        let rest = GrowingName.Drawing(growth: 0, ratio: ratio, sizes: oneLine)
        #expect(abs(rest.smallScale - 1) < 0.0001)
        #expect(rest.largeScale == CGSize(width: 1, height: 1))
        #expect(rest.largeOpacity == 0)
    }

    @Test("A name is drawn with a line break where each measured line starts, its spaces dropped")
    func linesAtMeasuredStarts() {
        let title = "Neutral-grip weighted pull-up with a pause at the top"
        let breaks = GrowingName.LineBreaks(title: title, starts: [22, 43])
        #expect(breaks
            .lines(of: title) == "Neutral-grip weighted\npull-up with a pause\nat the top")
        // A word wider than the line splits where the system split it, with no hyphen.
        let word = "Supercalifragilisticexpialidocious squat"
        #expect(GrowingName.LineBreaks(title: word, starts: [20]).lines(of: word)
            == "Supercalifragilistic\nexpialidocious squat")
    }

    @Test("A name on one line, or measured for another title, is drawn as it is")
    func linesUnbroken() {
        #expect(GrowingName.LineBreaks(title: "Plank", starts: []).lines(of: "Plank") == "Plank")
        let squat = GrowingName.LineBreaks(title: "Barbell back squat", starts: [8])
        #expect(squat.lines(of: "Barbell front squat") == "Barbell front squat")
        // Starts past the title's end, as a stale measure could hold, leave it whole.
        #expect(GrowingName.LineBreaks(title: "Plank", starts: [9]).lines(of: "Plank") == "Plank")
    }

    @Test("Before both sizes are measured, the font sizes' ratio scales both ways")
    func unmeasured() {
        let drawing = GrowingName.Drawing(growth: 0.5, ratio: ratio, sizes: .init())
        let scale = ratioScale(0.5)
        #expect(abs(drawing.largeScale.width - scale) < 0.0001)
        #expect(abs(drawing.largeScale.height - scale) < 0.0001)
    }
}
