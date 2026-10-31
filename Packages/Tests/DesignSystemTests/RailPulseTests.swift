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
        "Once a run is over, its pulse draws nothing, the plop settled over the lit node",
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
        // It goes as the plop settles over the lit node, before the move ends.
        let gone = run.duration - 1.0 / 60
        #expect(abs(gone - SetMotion.landing(way) - SetMotion.plop) < 1e-9)
        #expect(gone <= SetMotion.move(way))
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

    @Test(
        "Nothing moves until the pulse has landed and mostly plopped; then the shift runs",
        arguments: [SetMotion.Way.down, .loop],
    )
    @MainActor
    func beats(way: SetMotion.Way) {
        // Half a second across, slow enough to watch it travel, the whole move about 1.25 s.
        #expect(abs(SetMotion.landing(way) - 0.51) < 0.02)
        #expect(abs(SetMotion.move(way) - 1.25) < 0.05)
        // The shift and the parts going hold until a beat after the landing, the wiggle mostly
        // settled, so the landing plays on a still screen.
        let start = SetMotion.moveShiftStart(way)
        #expect(abs(start - SetMotion.landing(way) - SetMotion.landingHold) < 1e-9)
        #expect(abs(SetMotion.squash(at: SetMotion.landingHold)) < 0.25)
        #expect(SetMotion.leaveDelay(.figures, way: way) == start)
        #expect(SetMotion.detailOut(way: way) == .easeIn(duration: 0.06).delay(start))
        // Bottom first out, every part gone before the first comes in, top first, by the end.
        #expect(SetMotion.leaveDelay(.figures, way: way) < SetMotion.leaveDelay(.progress, way: way))
        #expect(SetMotion.leaveDelay(.progress, way: way) + SetMotion.leaveFade
            <= SetMotion.arriveDelay(.progress, way: way) + 1e-9)
        #expect(SetMotion.arriveDelay(.progress, way: way)
            < SetMotion.arriveDelay(.figures, way: way))
        #expect(SetMotion.arriveDelay(.figures, way: way) < SetMotion.shiftEnd(way))
        #expect(abs(SetMotion.shiftEnd(way) - start - SetMotion.moveShift) < 1e-9)
        // A round's roll shows on the grown row, within the move.
        #expect(SetMotion.roundRoll(way) > SetMotion.arriveDelay(.progress, way: way))
        #expect(SetMotion.roundRoll(way) < SetMotion.move(way))
        #expect(abs(SetMotion.move(way) - SetMotion.shiftEnd(way)) < 0.02)
    }
}
