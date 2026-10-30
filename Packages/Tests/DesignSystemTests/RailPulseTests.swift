import CoreGraphics
import SwiftUI
import Testing
@testable import DesignSystem

/// The way a pulse goes between two nodes, and the move's timings, from plain numbers.
@Suite("Rail pulse")
struct RailPulseTests {
    @Test("Down the rail, the route is the straight line from node to node")
    func line() {
        let route = RailRoute.line(from: CGPoint(x: 22, y: 30), to: CGPoint(x: 22, y: 94))
        #expect(route.length == 64)
        #expect(route.point(at: 32) == CGPoint(x: 22, y: 62))
        #expect(route.point(at: -5) == CGPoint(x: 22, y: 30))
        #expect(route.point(at: 100) == CGPoint(x: 22, y: 94))
    }

    @Test("Up a loop, the route goes out to the loop's line, up it, and back into the first node")
    func loop() {
        let from = CGPoint(x: 22, y: 200)
        let to = CGPoint(x: 22, y: 72)
        let route = RailRoute.loop(from: from, to: to, x: 10, radius: 7)
        #expect(route.points.first == from)
        #expect(route.points.last == to)
        #expect(route.points.allSatisfy { $0.x >= 10 && $0.x <= 22 })
        // Halfway along, it is on the loop's line, halfway up.
        let middle = route.point(at: route.length / 2)
        #expect(abs(middle.x - 10) < 0.01)
        #expect(abs(middle.y - 136) < 0.5)
        // Longer than straight up, by the way out and back, less what the corners cut.
        #expect(route.length > 128 && route.length < 128 + 24)
    }

    @Test("A stretch of the route starts and ends where asked, with the corners between")
    func stretch() {
        let route = RailRoute.loop(
            from: CGPoint(x: 22, y: 200),
            to: CGPoint(x: 22, y: 72),
            x: 10,
            radius: 7,
        )
        let stretch = route.stretch(from: 5, to: route.length - 5)
        #expect(stretch.first == route.point(at: 5))
        #expect(stretch.last == route.point(at: route.length - 5))
        #expect(stretch.count > 4)
    }

    /// A pulse down a 64 pt route at the sizes the rail draws at the default text size.
    private func blob(_ time: Double, way: SetMotion.Way = .down) -> Path {
        PulseShape(
            time: time,
            route: RailRoute.line(from: .zero, to: CGPoint(x: 0, y: 64)),
            size: 14,
            restingSize: 10,
            way: way,
        ).path(in: .zero)
    }

    @Test("Before its run, the pulse draws nothing; setting off, it is the node left, round")
    func hidden() {
        #expect(blob(-1).isEmpty)
        let box = blob(SetMotion.travelStart).boundingRect
        #expect(abs(box.width - 14) < 0.01 && abs(box.height - 14) < 0.01)
        #expect(abs(box.midY) < 0.01)
    }

    @Test("The neck between two circles thins as they part, then snaps")
    func neck() {
        func neck(apart: CGFloat) -> Path? {
            PulseShape.neck(
                .init(center: .zero, radius: 5),
                .init(center: CGPoint(x: 0, y: apart), radius: 5),
                goo: 8,
            )
        }
        func waist(_ path: Path?) -> CGFloat {
            // The neck's width halfway between the circles.
            guard let path else { return 0 }
            let middle = path.boundingRect.midY
            return path.intersection(Path(CGRect(x: -50, y: middle - 0.1, width: 100, height: 0.2)))
                .boundingRect.width
        }
        #expect(waist(neck(apart: 12)) > waist(neck(apart: 18)))
        #expect(waist(neck(apart: 18)) > 0)
        #expect(neck(apart: 22) == nil)
        // One circle inside the other has no neck.
        #expect(PulseShape.neck(
            .init(center: .zero, radius: 7), .init(center: .zero, radius: 5), goo: 8,
        ) == nil)
    }

    @Test("Drawn out, the mass keeps its area, thinner the longer it is")
    func width() {
        #expect(abs(PulseShape.width(length: 14, size: 14) - 14) < 1e-9)
        let width = PulseShape.width(length: 42, size: 14)
        #expect(width < 14 / 2)
        let area = width * (42 - width) + .pi / 4 * width * width
        #expect(abs(area - .pi / 4 * 14 * 14) < 1e-6)
    }

    @Test("Landed, it plops: wider than tall, wiggling back to round by the plop's end")
    func plop() {
        let landing = SetMotion.landing(.down)
        let deepest = (1 ... 100).map { landing + SetMotion.plop * Double($0) / 100 }
            .map { blob($0).boundingRect }
            .max { $0.width < $1.width }
        #expect(abs((deepest?.width ?? 0) - 14 * 1.25) < 0.1)
        #expect(abs((deepest?.height ?? 0) - 14 * 0.8) < 0.1)
        // It swings the other way, taller than wide, at least twice.
        var swings = 0
        var wasWide = true
        for step in 1 ... 350 {
            let squash = SetMotion.squash(at: Double(step) / 1000)
            if wasWide, squash < 0 {
                swings += 1
            }
            wasWide = squash >= 0
        }
        #expect(swings >= 2)
        #expect(abs(SetMotion.squash(at: SetMotion.plop * 0.99)) < 0.05)
    }

    @Test(
        "Once a run is over, its pulse draws nothing, the plop gone into the lit node",
        arguments: [SetMotion.Way.down, .loop],
    )
    func runEnds(way: SetMotion.Way) {
        let run = KeyframeTimeline(initialValue: -1.0) { PulseShape.run(way) }
        // Where the animator rests once the run is over.
        for time in [run.value(progress: 1), run.value(time: run.duration)] {
            #expect(blob(time, way: way).isEmpty)
        }
        // Through the plop, it draws on the node.
        let plopping = blob(run.value(time: SetMotion.landing(way) + 0.01), way: way).boundingRect
        #expect(abs(plopping.midY - 64) < 0.01)
        // It goes as the node lights, which ends the move or comes just before its end.
        let gone = run.duration - 1.0 / 60
        #expect(abs(gone - SetMotion.lit(way)) < 1e-9)
        #expect(SetMotion.lit(way) <= SetMotion.move(way))
    }

    @Test("Up a loop, the travel shoots off, ends where it lands, and still moves as it lands")
    func loopTravel() {
        #expect(SetMotion.distance(at: 0, .loop) == 0)
        #expect(abs(SetMotion.distance(at: 1, .loop) - 1) < 1e-9)
        #expect(SetMotion.speed(at: 0, .loop) > SetMotion.speed(at: 0.5, .loop))
        #expect(SetMotion.speed(at: 1, .loop) > 0)
    }

    @Test("Down the rail, the travel eases in and out, fastest halfway, and only ever goes forward")
    func downTravel() {
        #expect(SetMotion.distance(at: 0, .down) == 0)
        #expect(abs(SetMotion.distance(at: 1, .down) - 1) < 1e-9)
        #expect(abs(SetMotion.distance(at: 0.5, .down) - 0.5) < 1e-9)
        #expect(SetMotion.speed(at: 0.5, .down) > SetMotion.speed(at: 0.1, .down))
        #expect(SetMotion.speed(at: 0.5, .down) > SetMotion.speed(at: 0.9, .down))
        var last = 0.0
        for step in 0 ... 100 {
            let distance = SetMotion.distance(at: Double(step) / 100, .down)
            #expect(distance >= last)
            last = distance
        }
    }

    @Test("Up a loop, the move takes about 0.75 s, the pulse leading and the shift settling after")
    @MainActor
    func loopBeats() {
        #expect(abs(SetMotion.move(.loop) - 0.75) < 0.1)
        // The pulse sets off first; the shift is under way as the parts go, not after a beat.
        #expect(SetMotion.travelStart < SetMotion.leaveDelay(.equipment))
        #expect(TetheredShift.progress(at: SetMotion.leaveDelay(.equipment) + SetMotion.leaveFade)
            > 0)
        // The pulse lands ahead of the shift, which settles a beat after.
        let landed = SetMotion.travelStart + SetMotion.travel(.loop)
        #expect(TetheredShift.progress(at: landed) > 0.6)
        #expect(TetheredShift.progress(at: landed) < 0.9)
        #expect(SetMotion.shiftEnd(.loop) > landed + 0.15)
        #expect(SetMotion.shiftEnd(.loop) < landed + 0.4)
        // Top first in, bottom first out, every part gone before the first comes in.
        #expect(SetMotion.arriveDelay(.progress) < SetMotion.arriveDelay(.slide))
        #expect(SetMotion.leaveDelay(.slide) < SetMotion.leaveDelay(.progress))
        #expect(SetMotion.leaveDelay(.progress) + SetMotion.leaveFade
            <= SetMotion.arriveDelay(.progress))
    }

    @Test("Down the rail, the exercise holds while the pulse travels; the shift starts as it lands")
    @MainActor
    func downBeats() {
        // Half a second across, slow enough to watch it travel.
        #expect(SetMotion.travel(.down) == 0.5)
        let landed = SetMotion.travelStart + SetMotion.travel(.down)
        #expect(SetMotion.landing(.down) == landed)
        // The shift and the parts going start together, just before the landing.
        #expect(abs(SetMotion.downShiftStart - (landed - 0.08)) < 1e-9)
        #expect(SetMotion.leaveDelay(.slide, waits: true) == SetMotion.downShiftStart)
        #expect(SetMotion.leaveDelay(.progress, waits: true) + SetMotion.leaveFade
            < SetMotion.arriveDelay(.progress, waits: true))
        #expect(abs(SetMotion.shiftEnd(.down) - SetMotion.downShiftStart - SetMotion.downShift)
            < 1e-9)
        // The next exercise's parts come in during the shift, top first.
        #expect(SetMotion.arriveDelay(.progress, waits: true)
            < SetMotion.arriveDelay(.slide, waits: true))
        #expect(SetMotion.arriveDelay(.slide, waits: true) < SetMotion.shiftEnd(.down))
        // The node lights as the plop settles, within the shift; the move ends with the shift.
        #expect(SetMotion.lit(.down) < SetMotion.shiftEnd(.down))
        #expect(abs(SetMotion.move(.down) - SetMotion.shiftEnd(.down)) < 1e-9)
    }

    @Test("The shift trails the pulse, only ever moves forward, and ends where it lands")
    func tether() {
        var last = 0.0
        for step in 0 ... 1000 {
            let time = Double(step) / 1000
            let progress = TetheredShift.progress(at: time)
            #expect(progress >= last)
            #expect(progress <= 1)
            #expect(progress <= TetheredShift.pulse(at: time) + 1e-9)
            last = progress
        }
        #expect(TetheredShift.progress(at: SetMotion.shiftEnd(.loop)) == 1)
    }
}
