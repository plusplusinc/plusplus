import SwiftUI
import Testing
@testable import DesignSystem

/// Where a ruler's values sit along its content (`RulerScale`): the offset that puts a value
/// under the line, the tick an offset rests on, and the anchor that places the value at any
/// ruler width. Each at the default spacing and at a larger one, as at the accessibility sizes,
/// since the spacing scales with Dynamic Type.
@Suite("Ruler scale")
struct RulerScaleTests {
    private static let weight = (range: 5.0 ... 1000.0, tick: 0.5)
    private static let rest = (range: 0.0 ... 600.0, tick: 5.0)
    private nonisolated static let spacings: [CGFloat] = [8, 10, 22.4]

    @Test(
        "A value's offset reads back as that value, for every tick",
        arguments: spacings,
    )
    func offsetRoundTrips(spacing: CGFloat) {
        for ruler in [Self.weight, Self.rest] {
            let scale = RulerScale(range: ruler.range, tick: ruler.tick, spacing: spacing)
            for index in 0 ..< scale.count {
                let value = ruler.range.lowerBound + Double(index) * ruler.tick
                #expect(scale.value(at: scale.offset(of: value)) == value)
            }
        }
    }

    @Test("Offsets past either end read as the end's value")
    func offsetsHeldToTheRange() {
        let scale = RulerScale(range: Self.rest.range, tick: Self.rest.tick, spacing: 10)
        #expect(scale.value(at: -40) == 0)
        #expect(scale.value(at: 1_000_000) == 600)
        #expect(scale.offset(of: 900) == scale.offset(of: 600))
    }

    @Test("A value off the ticks sits between its two, where it falls")
    func offTickValueSitsBetweenTicks() {
        let scale = RulerScale(range: Self.weight.range, tick: Self.weight.tick, spacing: 8)
        // 27.3 lb is 0.6 of a tick past 27.
        #expect(abs(scale.offset(of: 27.3) - (scale.offset(of: 27) + 0.6 * 8)) < 1e-9)
    }

    /// Wherever the system would stop a flick, the ruler rests with a tick under the line, a
    /// rest's always a multiple of its 5 s tick.
    @Test("A scroll's target is always a tick", arguments: spacings)
    func targetIsATick(spacing: CGFloat) {
        let scale = RulerScale(range: Self.rest.range, tick: Self.rest.tick, spacing: spacing)
        for x in stride(from: CGFloat(0), through: scale.offset(of: 600), by: 1.7) {
            let target = scale.snapped(x)
            let value = scale.value(at: target)
            #expect(abs(scale.offset(of: value) - target) < 1e-6)
            #expect(value.truncatingRemainder(dividingBy: Self.rest.tick) == 0)
            #expect(abs(target - x) <= spacing / 2 + 1e-6)
        }
    }

    /// The ruler's content leads and trails by half its width less half a tick, so offset 0 puts
    /// the first tick under the line. Its anchor has to land the value there at any width, the
    /// first layout's included: an offset set before that room existed sat half the ruler's
    /// width of ticks past the value (27.5 lb read 39.5 under the line).
    @Test(
        "An anchor puts the value under the line at any width",
        arguments: [CGFloat(120), 390, 1024],
    )
    func anchorCentersTheValue(width: CGFloat) {
        for spacing in Self.spacings {
            let scale = RulerScale(
                range: Self.weight.range,
                tick: Self.weight.tick,
                spacing: spacing,
            )
            let room = max(0, width / 2 - spacing / 2)
            let contentWidth = room * 2 + CGFloat(scale.count) * spacing
            for value in [5, 27.5, 140, 1000] {
                let offset = scale.anchor(of: value).x * (contentWidth - width)
                let underLine = offset + width / 2 - room - spacing / 2
                #expect(abs(underLine - scale.offset(of: value)) < 1e-6)
            }
        }
    }
}
