import Testing
@testable import PlusPlus

@Suite("Rest notification content")
struct RestNotificationTests {
    @Test("Body names the upcoming set and exercise")
    func body() {
        #expect(RestNotification.body(exerciseName: "Bench Press", setNumber: 3) == "Set 3 — Bench Press")
        #expect(RestNotification.title == "Rest over")
    }

    @Test("Identifier is stable so a new rest replaces the pending one")
    func identifier() {
        #expect(RestNotification.identifier == "rest-end")
    }
}
