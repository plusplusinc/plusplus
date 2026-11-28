import Foundation
import Testing
@testable import WorkoutStore

@Suite("A top set and its change")
struct TopSetTests {
    private typealias Fixture = LogFixture

    private func top(_ sets: [LoggedSet]) -> TopSet {
        Fixture.workoutSession(daysAgo: 0, sets).loggedExercises(in: .builtIn)[0].topSet
    }

    @Test("With weight the heaviest wins, then the most reps at it")
    func heaviestThenReps() {
        let top = top([
            Fixture.set("bench", round: 1, .reps(10), Fixture.pounds(135)),
            Fixture.set("bench", round: 2, .reps(5), Fixture.pounds(150)),
            Fixture.set("bench", round: 3, .reps(6), Fixture.pounds(150)),
        ])
        #expect(top == TopSet(target: .reps(6), weight: Fixture.pounds(150)))
    }

    @Test("Reps alone and time take the most and the longest")
    func repsAndTime() {
        #expect(top([
            Fixture.set("pull-up", round: 1, .reps(6)),
            Fixture.set("pull-up", round: 2, .reps(8)),
        ]).target == .reps(8))
        #expect(top([
            Fixture.set("plank", round: 1, .time(seconds: 45)),
            Fixture.set("plank", round: 2, .time(seconds: 30)),
        ]).target == .time(seconds: 45))
    }

    @Test("Up, same, down, first, and changed")
    func changes() {
        let eight135 = TopSet(target: .reps(8), weight: Fixture.pounds(135))
        let five150 = TopSet(target: .reps(5), weight: Fixture.pounds(150))
        #expect(five150.change(from: eight135) == .up(.weight(Fixture.pounds(15))))
        #expect(eight135.change(from: five150) == .down(.weight(Fixture.pounds(15))))
        #expect(eight135.change(from: eight135) == .same)
        #expect(eight135.change(from: nil) == .first)
        let time = TopSet(target: .time(seconds: 30), weight: nil)
        #expect(time.change(from: eight135) == .changed)
        let more = TopSet(target: .reps(10), weight: Fixture.pounds(135))
        #expect(more.change(from: eight135) == .up(.reps(2, withWeight: true)))
    }

    @Test("Bodyweight to weighted is a gain of the weight")
    func bodyweightToWeighted() {
        let bodyweight = TopSet(target: .reps(10), weight: nil)
        let weighted = TopSet(target: .reps(6), weight: Fixture.pounds(10))
        #expect(weighted.change(from: bodyweight) == .up(.weight(Fixture.pounds(10))))
    }

    @Test("Pounds against kilograms compare by mass, the gain in the later unit")
    func units() {
        let pounds = TopSet(target: .reps(5), weight: Fixture.pounds(100))
        let kilograms = TopSet(target: .reps(5), weight: Weight(50, .kilograms))
        #expect(kilograms.change(from: pounds) == .up(.weight(Weight(4.64, .kilograms))))
        let same = TopSet(target: .reps(5), weight: Weight(45.359237, .kilograms))
        #expect(same.change(from: pounds) == .same)
    }
}
