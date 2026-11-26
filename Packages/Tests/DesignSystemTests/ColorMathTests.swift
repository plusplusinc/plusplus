import Testing
@testable import DesignSystem

/// The arithmetic Void's colors are worked out with. What it makes of them is held by
/// `VoidTests`; these hold the steps it is made of.
@Suite("Color math")
nonisolated struct ColorMathTests {
    @Test("sRGB to OKLab and back returns the color within one 8-bit step")
    func oklabRoundTrips() {
        for hex: UInt32 in [0x000000, 0xFFFFFF, 0x17191D, 0x5AA2FF, 0xFF9F45, 0x7C3AED] {
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
        let (from, to) = (RGB(0x17191D), RGB(0xE8EAEE))
        #expect(contrast(mix(from, to, 0), from) < 1.01)
        #expect(contrast(mix(from, to, 1), to) < 1.01)
    }

    @Test(
        "A nudge moves lightness only away from the ground, and stops at the first step that holds",
    )
    func nudgeStopsAtRatio() {
        let background = RGB(0xF6EFE2)
        let blue = RGB(0x3A8FD8)
        let nudged = nudge(blue, to: 4.5, on: [background], awayFrom: background)
        #expect(contrast(nudged, background) >= 4.5)
        #expect(OKLab(nudged).lightness < OKLab(blue).lightness)
        let oneStepBack = withLightness(blue, OKLab(nudged).lightness + 0.01)
        #expect(contrast(oneStepBack, background) < 4.5)
        let passing = RGB(0x2B251D)
        #expect(nudge(passing, to: 4.5, on: [background], awayFrom: background) == passing)
    }
}
