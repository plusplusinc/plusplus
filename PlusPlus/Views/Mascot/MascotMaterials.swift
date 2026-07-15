import SwiftUI
import UIKit
import RealityKit

/// The mascot's material set, resolved from Theme for one color scheme.
/// RealityKit materials are not trait-aware, so the palette is rebuilt
/// from the resolved UIColors whenever the scheme changes (MascotView's
/// update closure re-applies it). Color jobs: the body is warm neutral
/// ink, the "+" eyes are accent green — the mascot's face IS the ++
/// mark, and green is the glyph's color everywhere in the app.
struct MascotPalette: Equatable {
    let scheme: ColorScheme

    private var traits: UITraitCollection {
        UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
    }

    private func resolved(_ color: Color) -> UIColor {
        UIColor(color).resolvedColor(with: traits)
    }

    enum Role {
        case body      // torso, head, limbs
        case hand      // palms, fingers, feet: a step warmer/darker
        case eye       // the "+" glyphs, unlit so they always read
        case ground    // the platform disc
        case bar       // barbell/dumbbell handles
        case plate     // plates and dumbbell heads
    }

    @MainActor
    func material(for role: Role) -> any RealityKit.Material {
        switch role {
        case .body:
            return SimpleMaterial(color: resolved(Theme.borderStrong), roughness: 0.8, isMetallic: false)
        case .hand:
            return SimpleMaterial(color: resolved(Theme.supersetLoop), roughness: 0.85, isMetallic: false)
        case .eye:
            return UnlitMaterial(color: resolved(Theme.accent))
        case .ground:
            return SimpleMaterial(color: resolved(Theme.surfaceRaised), roughness: 0.95, isMetallic: false)
        case .bar:
            return SimpleMaterial(color: resolved(Theme.supersetLoop), roughness: 0.35, isMetallic: true)
        case .plate:
            return SimpleMaterial(color: resolved(Theme.primaryFill), roughness: 0.6, isMetallic: false)
        }
    }
}
