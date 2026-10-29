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

    @Test("Before its run and after it, the pulse draws nothing")
    func hidden() {
        let route = RailRoute.line(from: .zero, to: CGPoint(x: 0, y: 64))
        let shape = PulseShape(time: -1, route: route, lineWidth: 2)
        #expect(shape.path(in: .zero).isEmpty)
        let landed = PulseShape(time: PulseShape.end, route: route, lineWidth: 2)
        // Collapsed into a dot centered on the node, twice the line's width.
        let box = landed.path(in: .zero).boundingRect
        #expect(abs(box.height - 4) < 0.01)
        #expect(abs(box.midY - 64) < 0.01)
    }

    @Test("Once a run is over, its pulse draws nothing, the dot on the node gone too")
    func runEnds() {
        let route = RailRoute.line(from: .zero, to: CGPoint(x: 0, y: 64))
        let run = KeyframeTimeline(initialValue: -1.0) { PulseShape.run }
        // Where the animator rests once the run is over.
        for time in [run.value(progress: 1), run.value(time: run.duration)] {
            #expect(PulseShape(time: time, route: route, lineWidth: 2).path(in: .zero).isEmpty)
        }
        // Through the hold, the dot is on the node.
        let holding = run.value(time: run.duration - SetMotion.dotHold / 2)
        #expect(!PulseShape(time: holding, route: route, lineWidth: 2).path(in: .zero).isEmpty)
    }

    @Test("The travel shoots off, ends where it lands, and still moves as it lands")
    func travel() {
        #expect(SetMotion.distance(at: 0) == 0)
        #expect(abs(SetMotion.distance(at: 1) - 1) < 1e-9)
        #expect(SetMotion.speed(at: 0) > SetMotion.speed(at: 0.5))
        #expect(SetMotion.speed(at: 1) > 0)
    }

    @Test("The move takes about 0.7 s, one shift the pulse lands with, parts out before in")
    @MainActor
    func beats() {
        #expect(abs(SetMotion.move - 0.7) < 0.1)
        // The row starts to shift as the parts go, not after a beat.
        #expect(SetMotion.shiftStart < SetMotion.leaveDelay(.equipment) + SetMotion.leaveFade)
        // The pulse lands in the shift's last fifth, as the next row comes to rest.
        let landed = SetMotion.travelStart + SetMotion.travel
        #expect(landed > SetMotion.shiftStart + SetMotion.shift * 0.7)
        #expect(landed < SetMotion.shiftStart + SetMotion.shift)
        // Top first in, bottom first out, every part gone before the first comes in.
        #expect(SetMotion.arriveDelay(.progress) < SetMotion.arriveDelay(.slide))
        #expect(SetMotion.leaveDelay(.slide) < SetMotion.leaveDelay(.progress))
        #expect(SetMotion.leaveDelay(.progress) + SetMotion.leaveFade
            <= SetMotion.arriveDelay(.progress))
    }
}
