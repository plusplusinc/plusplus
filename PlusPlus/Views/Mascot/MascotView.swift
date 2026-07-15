import SwiftUI
import RealityKit
import PlusPlusKit

/// The 3D viewport: a non-AR RealityView (virtual camera — no ARKit,
/// no camera permission) holding the rig, two directional lights, and
/// a perspective camera. `.preview` is the inline card's fixed-angle
/// auto-loop; `.demo` adds the orbit camera controls for the sheet.
struct MascotView: View {
    enum Mode {
        case preview
        case demo
    }

    let playback: MascotPlayback
    let mode: Mode

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// make-closure products that must outlive the closure. A class so
    /// the make closure can write into SwiftUI state it doesn't own.
    @State private var holder = SceneHolder()

    @MainActor
    final class SceneHolder {
        var rig: MascotRig?
        var subscription: EventSubscription?
        var palette: MascotPalette?
    }

    var body: some View {
        // Observation anchor: the frozen step-through advances by
        // writing manualPhase; reading it here re-runs the update
        // closure, which re-applies the rig.
        let _ = playback.manualPhase
        realityView
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
            .onAppear { playback.reduceMotion = reduceMotion }
            .onChange(of: reduceMotion) { playback.reduceMotion = reduceMotion }
            .onDisappear {
                holder.subscription?.cancel()
                holder.subscription = nil
            }
    }

    private var realityView: some View {
        let view = RealityView { content in
            content.camera = .virtual

            let palette = MascotPalette(scheme: colorScheme)
            let rig = MascotRig(animation: playback.animation, palette: palette)
            content.add(rig.container)
            holder.rig = rig
            holder.palette = palette

            addLights(to: &content)
            addCamera(to: &content)
            if mode == .demo {
                content.cameraTarget = rig.chestTarget
            }

            // First frame before any tick, so a frozen mascot still
            // stands in its characteristic pose.
            let initial = playback.frozenSample
            MascotPoseApplier.apply(initial.pose, face: initial.face, to: rig)

            // The clock: one subscription, delta-timed, checked against
            // frozen/paused every frame. Weak captures + the explicit
            // cancel in onDisappear break the cycle the token would
            // otherwise form (subscription retains closure retains
            // holder retains subscription) — dismissed viewports must
            // not leak their entity trees.
            holder.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak holder, weak playback] event in
                MainActor.assumeIsolated {
                    guard let rig = holder?.rig,
                          let sample = playback?.tick(deltaTime: event.deltaTime) else { return }
                    MascotPoseApplier.apply(sample.pose, face: sample.face, to: rig)
                }
            }
        } update: { _ in
            guard let rig = holder.rig else { return }
            // Scheme flip: re-resolve materials.
            let palette = MascotPalette(scheme: colorScheme)
            if palette != holder.palette {
                holder.palette = palette
                rig.apply(palette: palette)
            }
            // Frozen step-through: the sheet moved the cursor.
            if playback.frozen {
                let sample = playback.frozenSample
                MascotPoseApplier.apply(sample.pose, face: sample.face, to: rig)
            }
        }
        return mode == .demo ? AnyView(view.realityViewCameraControls(.orbit)) : AnyView(view.allowsHitTesting(false))
    }

    private var accessibilityDescription: String {
        let name = playback.animation.exerciseName
        return playback.frozen
            ? "Mascot posed mid \(name)"
            : "Animated mascot demonstrating \(name)"
    }

    private func addLights(to content: inout some RealityViewContentProtocol) {
        // A warm key from the front upper left (with soft shadows) and
        // a dim cool fill from behind right — deterministic and
        // asset-free, no image-based lighting. Tints live beside the
        // palette (MascotLighting): scene light, not UI chrome, so not
        // Theme — but tunable in one place.
        let key = DirectionalLight()
        key.light.intensity = MascotLighting.keyIntensity
        key.light.color = MascotLighting.keyColor
        key.shadow = DirectionalLightComponent.Shadow()
        key.look(at: .zero, from: [0.9, 1.6, 1.3], relativeTo: nil)
        content.add(key)

        let fill = DirectionalLight()
        fill.light.intensity = MascotLighting.fillIntensity
        fill.light.color = MascotLighting.fillColor
        fill.look(at: .zero, from: [-1.1, 0.8, -0.9], relativeTo: nil)
        content.add(fill)
    }

    private func addCamera(to content: inout some RealityViewContentProtocol) {
        // Floor moves run along the z axis, so their camera sits more
        // to the side; standing moves get the front three-quarter view.
        let isFloorMove = playback.animation.restingPose.rootRotation.pitch > .pi / 4
        let camera = PerspectiveCamera()
        let position: SIMD3<Float> = isFloorMove ? [1.35, 0.75, 0.95] : [0.5, 0.8, 1.55]
        let target: SIMD3<Float> = isFloorMove ? [0, 0.28, 0] : [0, 0.56, 0]
        camera.look(at: target, from: position, relativeTo: nil)
        content.add(camera)
    }
}
