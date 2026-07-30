import Foundation
import Testing
@testable import PlusPlusKit

@Suite("ExerciseModality")
struct ExerciseModalityTests {
    @Test("Gear-specific families win whatever the metrics say")
    func gearSpecific() {
        #expect(ExerciseModality.derive(equipmentNames: ["Rowing Machine"], metrics: [.distance, .duration, .pace]) == .rowing)
        #expect(ExerciseModality.derive(equipmentNames: ["Jump Rope"], metrics: [.duration]) == .jumpRope)
        #expect(ExerciseModality.derive(equipmentNames: ["Bicycle"], metrics: [.distance, .pace]) == .cycling)
        #expect(ExerciseModality.derive(equipmentNames: ["Stationary Bike"], metrics: [.duration, .calories]) == .cycling)
        #expect(ExerciseModality.derive(equipmentNames: ["Air Bike"], metrics: [.calories, .duration]) == .cycling)
    }

    @Test("Load wins over distance: carries and sled work read as strength")
    func loadedCarries() {
        #expect(ExerciseModality.derive(equipmentNames: ["Farmers Walk Handles"], metrics: [.weight, .distance, .duration]) == .strength)
        #expect(ExerciseModality.derive(equipmentNames: ["Sled"], metrics: [.weight, .distance]) == .strength)
    }

    @Test("Named console gear resolves to its own sport, not generic cardio")
    func consoleGear() {
        // Both of these used to land on `.cardio`. Naming them is what
        // lets Health file a treadmill run as a run and a stair session
        // as stair climbing, instead of as strength training.
        #expect(ExerciseModality.derive(equipmentNames: ["Treadmill"], metrics: [.speed, .incline, .duration]) == .running)
        #expect(ExerciseModality.derive(equipmentNames: ["Stair Climber"], metrics: [.duration, .calories]) == .stairClimbing)
        #expect(ExerciseModality.derive(equipmentNames: ["Vertical Climber"], metrics: [.duration]) == .stairClimbing)
        #expect(ExerciseModality.derive(equipmentNames: ["Elliptical"], metrics: [.duration, .resistance]) == .elliptical)
    }

    @Test("Unnamed road work falls back to generic cardio")
    func genericCardio() {
        // Running and Walking are equipment-free and metrically identical,
        // so derivation genuinely cannot tell them apart — the catalog
        // authors those. `.cardio` is the honest fallback.
        #expect(ExerciseModality.derive(equipmentNames: [], metrics: [.distance, .duration, .pace]) == .cardio)
        #expect(ExerciseModality.derive(equipmentNames: ["Ski Erg"], metrics: [.distance, .pace]) == .cardio)
    }

    @Test("Everything else is strength, including duration-only holds")
    func strengthDefault() {
        #expect(ExerciseModality.derive(equipmentNames: ["Barbell"], metrics: [.weight, .reps]) == .strength)
        #expect(ExerciseModality.derive(equipmentNames: [], metrics: [.reps]) == .strength)
        // A plank tracks duration alone; derivation must NOT call it
        // cardio (or flexibility — that case is authored only).
        #expect(ExerciseModality.derive(equipmentNames: [], metrics: [.duration]) == .strength)
    }

    @Test("isCardio splits the families the way the app asks about them")
    func cardioFlag() {
        let cardioFamilies: [ExerciseModality] = [
            .cardio, .running, .walking, .hiking, .cycling,
            .rowing, .swimming, .elliptical, .stairClimbing, .jumpRope,
        ]
        let allCardio = cardioFamilies.allSatisfy(\.isCardio)
        #expect(allCardio)
        #expect(!ExerciseModality.strength.isCardio)
        // An elliptical tracks neither distance nor pace, which is exactly
        // why the old `Routine.isCardio` test missed it.
        #expect(ExerciseModality.elliptical.isCardio)
        #expect(!ExerciseModality.flexibility.isCardio)
    }

    @Test("Cross-cardio swaps keep partial credit after the family split")
    func similarityPartialCredit() {
        // Splitting `.cardio` into named families made an elliptical score
        // ZERO against a treadmill run — the same as a burpee — because a
        // straight equality test has no middle. It is a substitution
        // ranker; an elliptical is a far better answer than a barbell.
        #expect(ExerciseSimilarity.modalityScore(.running, .running) == 1.0)
        #expect(ExerciseSimilarity.modalityScore(.elliptical, .running) == 0.5)
        #expect(ExerciseSimilarity.modalityScore(.rowing, .cycling) == 0.5)
        #expect(ExerciseSimilarity.modalityScore(.strength, .running) == 0.0)
        #expect(ExerciseSimilarity.modalityScore(.strength, .flexibility) == 0.5)
    }

    @Test("An outdoor effort we could not name still beats Mixed Cardio")
    func outdoorFallback() {
        // Belt and braces for a future catalog row that forgets to author
        // its modality: a workout arriving with a GPS route is a run, not
        // an unlabelled console piece.
        let outdoor = SessionModality(primary: .cardio, isMixed: false, isOutdoor: true)
        let indoor = SessionModality(primary: .cardio, isMixed: false, isOutdoor: false)
        #expect(outdoor.primary == .cardio)
        #expect(indoor.primary == .cardio)
        // The mapping itself is HealthKit-only, so assert the input the
        // map keys on rather than the HK type (unavailable on Linux).
        #expect(outdoor.isOutdoor)
        #expect(!indoor.isOutdoor)
    }

    @Test("Every family carries search terms and a display name")
    func metadata() {
        let allLabelled = ExerciseModality.allCases.allSatisfy {
            !$0.searchTerms.isEmpty && !$0.displayName.isEmpty
        }
        #expect(allLabelled)
        // "cardio" reaches every cardio family, which is the one word
        // someone types when they don't know what the app calls it.
        let reachedByCardio = ExerciseModality.allCases
            .filter(\.isCardio)
            .allSatisfy { $0.searchTerms.contains("cardio") }
        #expect(reachedByCardio)
    }
}
