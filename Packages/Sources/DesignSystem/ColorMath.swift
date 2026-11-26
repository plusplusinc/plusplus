import Foundation
import SwiftUI

/// An opaque sRGB color as gamma-encoded components from 0 to 1: what a hex literal names.
nonisolated struct RGB: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    /// `RGB(0x158645)`.
    init(_ hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// A resolved color's sRGB components, its opacity dropped.
    init(_ resolved: Color.Resolved) {
        red = Double(resolved.red)
        green = Double(resolved.green)
        blue = Double(resolved.blue)
    }

    func resolved(opacity: Double = 1) -> Color.Resolved {
        Color.Resolved(
            colorSpace: .sRGB,
            red: Float(red),
            green: Float(green),
            blue: Float(blue),
            opacity: Float(opacity),
        )
    }

    /// WCAG 2's relative luminance.
    var luminance: Double {
        0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    var isInGamut: Bool {
        [red, green, blue].allSatisfy { $0 >= -0.0005 && $0 <= 1.0005 }
    }

    var clamped: Self {
        Self(red: min(max(red, 0), 1), green: min(max(green, 0), 1), blue: min(max(blue, 0), 1))
    }
}

/// A color in OKLab: `lightness` from 0 to 1, and its two opponent axes.
nonisolated struct OKLab: Hashable, Sendable {
    var lightness: Double
    var greenRed: Double
    var blueYellow: Double

    init(lightness: Double, greenRed: Double, blueYellow: Double) {
        self.lightness = lightness
        self.greenRed = greenRed
        self.blueYellow = blueYellow
    }

    init(_ rgb: RGB) {
        let (red, green, blue) = (linear(rgb.red), linear(rgb.green), linear(rgb.blue))
        let long = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
        let medium = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
        let short = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
        lightness = 0.2104542553 * long + 0.7936177850 * medium - 0.0040720468 * short
        greenRed = 1.9779984951 * long - 2.4285922050 * medium + 0.4505937099 * short
        blueYellow = 0.0259040371 * long + 0.7827717662 * medium - 0.8086757660 * short
    }

    /// The hue angle in degrees, from -180 to 180.
    var hue: Double {
        atan2(blueYellow, greenRed) * 180 / .pi
    }

    /// How colorful it is: 0 for a gray.
    var chroma: Double {
        (greenRed * greenRed + blueYellow * blueYellow).squareRoot()
    }

    /// The straight-line distance between two colors in OKLab.
    func distance(to other: Self) -> Double {
        let lightness = lightness - other.lightness
        let greenRed = greenRed - other.greenRed
        let blueYellow = blueYellow - other.blueYellow
        return (lightness * lightness + greenRed * greenRed + blueYellow * blueYellow).squareRoot()
    }

    /// How far apart two colors' hues are, in degrees from 0 to 180.
    func hueDistance(to other: Self) -> Double {
        let distance = abs(hue - other.hue).truncatingRemainder(dividingBy: 360)
        return min(distance, 360 - distance)
    }

    /// Unclamped: a color outside sRGB comes back with a component outside 0 to 1.
    var rgb: RGB {
        let long = pow(lightness + 0.3963377774 * greenRed + 0.2158037573 * blueYellow, 3)
        let medium = pow(lightness - 0.1055613458 * greenRed - 0.0638541728 * blueYellow, 3)
        let short = pow(lightness - 0.0894841775 * greenRed - 1.2914855480 * blueYellow, 3)
        return RGB(
            red: gamma(4.0767416621 * long - 3.3077115913 * medium + 0.2309699292 * short),
            green: gamma(-1.2684380046 * long + 2.6097574011 * medium - 0.3413193965 * short),
            blue: gamma(-0.0041960863 * long - 0.7034186147 * medium + 1.7076147010 * short),
        )
    }
}

/// WCAG 2's contrast ratio of two opaque colors.
nonisolated func contrast(_ first: RGB, _ second: RGB) -> Double {
    let (one, two) = (first.luminance, second.luminance)
    return (max(one, two) + 0.05) / (min(one, two) + 0.05)
}

/// An OKLab mix from `from` toward `to`, `fraction` of the way; under 0 it goes past `from`,
/// away from `to`.
nonisolated func mix(_ from: RGB, _ to: RGB, _ fraction: Double) -> RGB {
    let (start, end) = (OKLab(from), OKLab(to))
    return inGamut(OKLab(
        lightness: start.lightness + (end.lightness - start.lightness) * fraction,
        greenRed: start.greenRed + (end.greenRed - start.greenRed) * fraction,
        blueYellow: start.blueYellow + (end.blueYellow - start.blueYellow) * fraction,
    ))
}

/// `color` at another OKLab lightness, its hue kept, its chroma reduced only as far as it must
/// be to stay in sRGB.
nonisolated func withLightness(_ color: RGB, _ lightness: Double) -> RGB {
    var lab = OKLab(color)
    lab.lightness = min(max(lightness, 0), 1)
    return inGamut(lab)
}

/// Moves `color`'s lightness away from `background` in steps of 0.01 until it has `ratio`
/// against every one of `grounds`, and stops at the first step that does. A color that already
/// has it comes back as it is.
nonisolated func nudge(
    _ color: RGB,
    to ratio: Double,
    on grounds: [RGB],
    awayFrom background: RGB,
) -> RGB {
    let step = OKLab(color).lightness >= OKLab(background).lightness ? 0.01 : -0.01
    var moved = color
    var lightness = OKLab(color).lightness
    while !grounds.allSatisfy({ contrast(moved, $0) >= ratio }), lightness > 0, lightness < 1 {
        lightness += step
        moved = withLightness(color, lightness)
    }
    return moved
}

/// Brings a color outside sRGB in by reducing its chroma, lightness and hue kept.
private nonisolated func inGamut(_ lab: OKLab) -> RGB {
    func scaled(_ scale: Double) -> RGB {
        OKLab(
            lightness: lab.lightness,
            greenRed: lab.greenRed * scale,
            blueYellow: lab.blueYellow * scale,
        ).rgb
    }
    guard !lab.rgb.isInGamut else { return lab.rgb.clamped }
    var (low, high) = (0.0, 1.0)
    for _ in 0 ..< 20 {
        let scale = (low + high) / 2
        if scaled(scale).isInGamut {
            low = scale
        } else {
            high = scale
        }
    }
    return scaled(low).clamped
}

private nonisolated func linear(_ value: Double) -> Double {
    value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
}

private nonisolated func gamma(_ value: Double) -> Double {
    let magnitude = abs(value)
    let encoded = magnitude <= 0.0031308 ? magnitude * 12.92 : 1.055 * pow(magnitude, 1 / 2.4) -
        0.055
    return value < 0 ? -encoded : encoded
}
