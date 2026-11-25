import Testing
@testable import DesignSystem

/// The arithmetic every base16 look is worked out with. What it makes of each palette is held by
/// `ThemeContrastTests`; these hold the steps it is made of.
@Suite("Color math")
nonisolated struct ColorMathTests {
    @Test("sRGB to OKLab and back returns the color within one 8-bit step")
    func oklabRoundTrips() {
        for hex: UInt32 in [0x000000, 0xFFFFFF, 0x2E3440, 0x88C0D0, 0xFE8019, 0x8839EF] {
            let color = RGB(hex)
            let back = OKLab(color).rgb
            for (one, two) in [
                (color.red, back.red),
                (color.green, back.green),
                (color.blue, back.blue),
            ] {
                #expect(abs(one - two) < 1.0 / 255, "\(String(hex, radix: 16)) came back off")
            }
        }
    }

    @Test("A mix at 0 and at 1 returns its ends")
    func mixReturnsEnds() {
        let (from, to) = (RGB(0x2E3440), RGB(0xE5E9F0))
        #expect(contrast(mix(from, to, 0), from) < 1.01)
        #expect(contrast(mix(from, to, 1), to) < 1.01)
    }

    @Test(
        "A nudge moves lightness only away from the ground, and stops at the first step that holds",
    )
    func nudgeStopsAtRatio() {
        let background = RGB(0xFDF6E3)
        let blue = RGB(0x268BD2)
        let nudged = nudge(blue, to: 4.5, on: [background], awayFrom: background)
        #expect(contrast(nudged, background) >= 4.5)
        #expect(OKLab(nudged).lightness < OKLab(blue).lightness)
        let oneStepBack = withLightness(blue, OKLab(nudged).lightness + 0.01)
        #expect(contrast(oneStepBack, background) < 4.5)
        let passing = RGB(0x073642)
        #expect(nudge(passing, to: 4.5, on: [background], awayFrom: background) == passing)
    }

    @Test("Hue distance takes the short way round, across the green end of the circle")
    func hueDistanceWraps() {
        // Hues of about 169° and -169°: 22.6° apart, not 337.4°.
        let (teal, green) = (
            OKLab(lightness: 0.6, greenRed: -0.1, blueYellow: -0.02),
            OKLab(lightness: 0.6, greenRed: -0.1, blueYellow: 0.02),
        )
        #expect(abs(teal.hueDistance(to: green) - 22.6) < 0.1)
        let (blue, yellow) = (
            OKLab(lightness: 0.6, greenRed: 0, blueYellow: -0.1),
            OKLab(lightness: 0.6, greenRed: 0, blueYellow: 0.1),
        )
        #expect(abs(blue.hueDistance(to: yellow) - 180) < 0.001)
    }
}
