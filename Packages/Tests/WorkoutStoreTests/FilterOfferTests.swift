import Testing
@testable import WorkoutStore

@Suite("Filter offers")
struct FilterOfferTests {
    private func choices(
        _ text: String,
        _ filter: ExerciseFilter = ExerciseFilter(),
    ) -> [FilterChoice] {
        FilterOffer.offers(in: text, given: filter).map(\.choice)
    }

    @Test("A choice's whole name offers it, ignoring case and punctuation")
    func wholeName() {
        #expect(choices("back") == [.muscle(.back)])
        #expect(choices("BACK") == [.muscle(.back)])
        #expect(choices("stretch") == [.kind(.stretch)])
        #expect(choices("Back!") == [.muscle(.back)])
    }

    @Test("Singular or plural offers the same choice")
    func singularOrPlural() {
        #expect(choices("leg") == [.muscle(.legs)])
        #expect(choices("legs") == [.muscle(.legs)])
        #expect(choices("dumbbell") == [.equipment(.piece(.dumbbells))])
        #expect(choices("dumbbells") == [.equipment(.piece(.dumbbells))])
        #expect(choices("stretches") == [.kind(.stretch)])
        #expect(choices("kettlebells") == [.equipment(.piece(.kettlebell))])
    }

    @Test("A name of several words offers its choice, however they are joined")
    func multiword() {
        #expect(choices("pull up bar") == [.equipment(.piece(.pullUpBar))])
        #expect(choices("pull-up bar") == [.equipment(.piece(.pullUpBar))])
        #expect(choices("pullupbar") == [.equipment(.piece(.pullUpBar))])
        #expect(choices("medicine ball") == [.equipment(.piece(.medicineBall))])
        #expect(choices("medicine balls") == [.equipment(.piece(.medicineBall))])
    }

    @Test("Bodyweight offers No equipment")
    func bodyweight() {
        #expect(choices("bodyweight") == [.equipment(.none)])
        #expect(choices("no equipment") == [.equipment(.none)])
    }

    @Test("Part of a word, or a name inside a longer word, offers nothing")
    func partOfAWord() {
        #expect(choices("bac").isEmpty)
        #expect(choices("backward").isEmpty)
        #expect(choices("pullup").isEmpty)
        #expect(choices("ball").isEmpty)
        #expect(choices("").isEmpty)
    }

    @Test("A choice already on is not offered; a different kind is")
    func alreadyOn() {
        let back = ExerciseFilter(muscleGroups: [.back], kind: .stretch)
        #expect(choices("back", back).isEmpty)
        #expect(choices("stretch", back).isEmpty)
        #expect(choices("legs", back) == [.muscle(.legs)])
        #expect(choices("strength", back) == [.kind(.strength)])
    }

    @Test("Several offers come in typed order, each leaving the other's word")
    func several() {
        let offers = FilterOffer.offers(in: "back dumbbell", given: ExerciseFilter())
        #expect(offers.map(\.choice) == [.muscle(.back), .equipment(.piece(.dumbbells))])
        #expect(offers.map(\.remainingText) == ["dumbbell", "back"])
    }

    @Test("Taking an offer leaves the rest of the text as typed, less one space by the word")
    func remainingText() {
        // A space typed after the last word stays, so the next word starts apart.
        #expect(FilterOffer.offers(in: "squat back ", given: ExerciseFilter()).first?
            .remainingText == "squat ")
        let offer = FilterOffer.offers(in: "barbell  back squat", given: ExerciseFilter())
            .first { $0.choice == .muscle(.back) }
        #expect(offer?.remainingText == "barbell  squat")
        let whole = FilterOffer.offers(in: "back", given: ExerciseFilter()).first
        #expect(whole?.remainingText.isEmpty == true)
        #expect(FilterOffer.offers(in: "pull up bar rows", given: ExerciseFilter()).first?
            .remainingText == "rows")
    }

    @Test("Taking turns the choice on: Muscle and Equipment add, Kind sets")
    func turnOn() {
        var filter = ExerciseFilter(muscleGroups: [.back], kind: .strength)
        filter.turnOn(.muscle(.legs))
        filter.turnOn(.kind(.stretch))
        filter.turnOn(.equipment(.none))
        #expect(filter.muscleGroups == [.back, .legs])
        #expect(filter.kind == .stretch)
        #expect(filter.equipment == [.none])
        #expect(filter.muscleLabel == "Back, Legs")
    }

    @Test("Search stays names only: an offer's word still finds names alone")
    func searchStaysNames() {
        let list = ExerciseList.builtIn
        #expect(list.matching("pullup").contains { $0.name == "Pull-up" })
        #expect(list.matching("back").allSatisfy { $0.name.lowercased().contains("back") })
    }
}
