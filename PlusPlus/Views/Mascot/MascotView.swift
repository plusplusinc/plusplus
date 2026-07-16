import SwiftUI
import RealityKit
import PlusPlusKit

/// The 3D viewport: a non-AR RealityView (virtual camera — no ARKit,
/// no camera permission) holding the rig, two directional lights, and
/// a perspective camera. `.preview` is the inline card's fixed-angle
/// auto-loop; `.demo` adds a HAND-ROLLED orbit + pinch camera. The
/// system `.realityViewCameraControls(.orbit)` is deliberately not
/// used: on device it ignored the authored camera (build 80 opened the
/// plank demo inside the mascot's face) and its zoom was unbounded —
/// this one starts from the per-move framing and clamps everything.
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
    @State private var orbit: OrbitState
    @State private var dragBase: (azimuth: Float, elevation: Float)?
    @State private var zoomBase: Float?

    @MainActor
    final class SceneHolder {
        var rig: MascotRig?
        var camera: PerspectiveCamera?
        var subscription: EventSubscription?
        var palette: MascotPalette?
    }

    /// Spherical camera state around a fixed target. Clamps keep the
    /// mascot on screen and the camera inside the room at every zoom.
    struct OrbitState {
        var azimuth: Float
        var elevation: Float
        var radius: Float
        var target: SIMD3<Float>
        /// Azimuth clamps to a window around the per-move framing: the
        /// room has three walls, and an unclamped orbit could face the
        /// open side (raw viewport background past the floor's edge).
        var azimuthRange: ClosedRange<Float> = 0...0

        static let elevationRange: ClosedRange<Float> = -0.05...1.25
        static let radiusRange: ClosedRange<Float> = 0.9...2.2

        var position: SIMD3<Float> {
            target + radius * SIMD3(
                sin(azimuth) * cos(elevation),
                sin(elevation),
                cos(azimuth) * cos(elevation)
            )
        }

        /// Floor moves run along the z axis, so their camera sits more
        /// to the side; standing moves get the front three-quarter view
        /// (the framing the build-80 pass confirmed on the curl).
        static func framing(for animation: ExerciseAnimation, mode: Mode) -> OrbitState {
            let isFloorMove = animation.restingPose.rootRotation.pitch > .pi / 4
            var state = isFloorMove
                ? OrbitState(azimuth: 1.15, elevation: 0.5, radius: 1.55, target: [0, 0.22, 0])
                : OrbitState(azimuth: 0.32, elevation: 0.33, radius: 1.6, target: [0, 0.55, 0])
            state.azimuthRange = (state.azimuth - 1.15)...(state.azimuth + 1.15)
            if mode == .preview {
                state.radius -= 0.15
            }
            return state
        }
    }

    init(playback: MascotPlayback, mode: Mode) {
        self.playback = playback
        self.mode = mode
        _orbit = State(initialValue: OrbitState.framing(for: playback.animation, mode: mode))
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
            let camera = PerspectiveCamera()
            camera.look(at: orbit.target, from: orbit.position, relativeTo: nil)
            content.add(camera)
            holder.camera = camera

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
            // Orbit/zoom state drives the camera.
            holder.camera?.look(at: orbit.target, from: orbit.position, relativeTo: nil)
            // Frozen step-through: the sheet moved the cursor.
            if playback.frozen {
                let sample = playback.frozenSample
                MascotPoseApplier.apply(sample.pose, face: sample.face, to: rig)
            }
        }
        return Group {
            if mode == .demo {
                view
                    .gesture(orbitDrag)
                    .simultaneousGesture(pinchZoom)
            } else {
                view.allowsHitTesting(false)
            }
        }
    }

    private var orbitDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let base = dragBase ?? (orbit.azimuth, orbit.elevation)
                if dragBase == nil {
                    dragBase = base
                }
                let azimuth = base.azimuth - Float(value.translation.width) * 0.008
                orbit.azimuth = min(max(azimuth, orbit.azimuthRange.lowerBound), orbit.azimuthRange.upperBound)
                let elevation = base.elevation + Float(value.translation.height) * 0.008
                orbit.elevation = min(max(elevation, OrbitState.elevationRange.lowerBound), OrbitState.elevationRange.upperBound)
            }
            .onEnded { _ in dragBase = nil }
    }

    private var pinchZoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = zoomBase ?? orbit.radius
                if zoomBase == nil {
                    zoomBase = base
                }
                let radius = base / Float(value.magnification)
                orbit.radius = min(max(radius, OrbitState.radiusRange.lowerBound), OrbitState.radiusRange.upperBound)
            }
            .onEnded { _ in zoomBase = nil }
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
}
