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
    /// One line at the small size, two at the large.
    private let wrapsAtLarge = GrowingName.Sizes(
        small: CGSize(width: 300, height: 22),
        large: CGSize(width: 340, height: 68),
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

    @Test("Breaking differently, the two crossfade, both scaled by the font sizes' ratio alone")
    func crossfadesWhenBreakingDifferently() {
        let drawing = GrowingName.Drawing(growth: 0.25, ratio: ratio, sizes: wrapsAtLarge)
        let scale = ratioScale(0.25)
        #expect(abs(drawing.largeScale.width - scale) < 0.0001)
        #expect(abs(drawing.largeScale.height - scale) < 0.0001)
        #expect(abs(drawing.smallScale - scale * ratio) < 0.0001)
        #expect(drawing.largeOpacity == 0.25)
    }

    @Test("As many lines broken at other words crossfade, like a different number of lines")
    func crossfadesWhenBreakingAtOtherWords() {
        // Two lines both ways, the widest far narrower at the large size than the ratio has it.
        let otherWords = GrowingName.Sizes(
            small: CGSize(width: 300, height: 44),
            large: CGSize(width: 330, height: 72),
        )
        let drawing = GrowingName.Drawing(growth: 0.25, ratio: ratio, sizes: otherWords)
        #expect(abs(drawing.largeScale.width - ratioScale(0.25)) < 0.0001)
        #expect(drawing.largeOpacity == 0.25)
    }

    @Test("Before both sizes are measured, the font sizes' ratio scales both ways")
    func unmeasured() {
        let drawing = GrowingName.Drawing(growth: 0.5, ratio: ratio, sizes: .init())
        let scale = ratioScale(0.5)
        #expect(abs(drawing.largeScale.width - scale) < 0.0001)
        #expect(abs(drawing.largeScale.height - scale) < 0.0001)
    }
}
