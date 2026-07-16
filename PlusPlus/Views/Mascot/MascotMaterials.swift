import SwiftUI
import UIKit
import RealityKit

/// Scene lighting tints — light, not UI chrome, so deliberately not
/// Theme colors; named here so the whole 3D look tunes in one file.
enum MascotLighting {
    static let keyIntensity: Float = 3200
    static let keyColor = UIColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1)
    static let fillIntensity: Float = 900
    static let fillColor = UIColor(red: 0.85, green: 0.9, blue: 1.0, alpha: 1)
}

/// The character's own colors — scene content like the lighting, not
/// UI chrome, and deliberately scheme-INDEPENDENT: a white robot is a
/// white robot in dark mode too (build-80 direction: "the robot more
/// white", ASIMO-adjacent white panels over dark joints).
enum MascotSkin {
    static let panel = UIColor(red: 0.95, green: 0.94, blue: 0.92, alpha: 1)
    static let joint = UIColor(red: 0.22, green: 0.21, blue: 0.20, alpha: 1)
    static let facePanel = UIColor(red: 0.16, green: 0.155, blue: 0.15, alpha: 1)
}

/// The mascot's material set, resolved from Theme for one color scheme
/// where the color IS thematic (equipment green = the brand accent;
/// the room drawn in surface tones). RealityKit materials are not
/// trait-aware, so the palette is rebuilt from resolved UIColors when
/// the scheme changes. Everything is MATTE — no metallic, per Dave.
struct MascotPalette: Equatable {
    let scheme: ColorScheme

    private var traits: UITraitCollection {
        UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
    }

    private func resolved(_ color: Color) -> UIColor {
        UIColor(color).resolvedColor(with: traits)
    }

    enum Role {
        case panel       // white body panels
        case joint       // charcoal joints, hands, soles, neck
        case facePanel   // the dark face plate the eyes live on
        case eye         // the "+" glyphs: accent green, unlit
        case ground      // the stage disc
        case floor       // the room floor (dot grid)
        case wall        // the room walls (dot grid, unlit backdrop)
        case equipment   // plates, dumbbell heads: accent green
        case equipmentDark // bar shafts, handles: darkened accent
    }

    @MainActor
    func material(for role: Role) -> any RealityKit.Material {
        switch role {
        case .panel:
            return SimpleMaterial(color: MascotSkin.panel, roughness: 0.6, isMetallic: false)
        case .joint:
            return SimpleMaterial(color: MascotSkin.joint, roughness: 0.85, isMetallic: false)
        case .facePanel:
            return SimpleMaterial(color: MascotSkin.facePanel, roughness: 0.5, isMetallic: false)
        case .eye:
            return UnlitMaterial(color: resolved(Theme.accent))
        case .ground:
            return SimpleMaterial(color: resolved(Theme.surfaceRaised), roughness: 0.95, isMetallic: false)
        case .floor:
            var material = SimpleMaterial(color: resolved(Theme.background), roughness: 0.95, isMetallic: false)
            if let texture = dotGridTexture() {
                material.color = .init(tint: .white, texture: .init(texture))
            }
            return material
        case .wall:
            var material = UnlitMaterial(color: resolved(Theme.background))
            if let texture = dotGridTexture() {
                material.color = .init(tint: .white, texture: .init(texture))
            }
            return material
        case .equipment:
            return SimpleMaterial(color: resolved(Theme.accent), roughness: 0.7, isMetallic: false)
        case .equipmentDark:
            return SimpleMaterial(color: darkened(resolved(Theme.accent), by: 0.45), roughness: 0.75, isMetallic: false)
        }
    }

    private func darkened(_ color: UIColor, by fraction: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let keep = 1 - fraction
        return UIColor(red: r * keep, green: g * keep, blue: b * keep, alpha: a)
    }

    /// The room's dot-grid wallpaper, generated at runtime (no bundled
    /// textures): the full grid is baked into one image so no material
    /// tiling transform is needed.
    @MainActor
    func dotGridTexture() -> TextureResource? {
        let size = 1024
        let cells = 16
        let dotRadius: CGFloat = 3.5
        let background = resolved(Theme.background)
        let dot = resolved(Theme.border)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { context in
            background.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            dot.setFill()
            let spacing = CGFloat(size) / CGFloat(cells)
            for row in 0...cells {
                for column in 0...cells {
                    let center = CGPoint(x: CGFloat(column) * spacing, y: CGFloat(row) * spacing)
                    let rect = CGRect(
                        x: center.x - dotRadius,
                        y: center.y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                    context.cgContext.fillEllipse(in: rect)
                }
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource.generate(from: cgImage, options: .init(semantic: .color))
    }
}
