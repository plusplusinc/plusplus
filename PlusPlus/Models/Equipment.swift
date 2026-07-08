import Foundation
import SwiftData

@Model
final class Equipment {
    var name: String
    var isBuiltIn: Bool
    /// Personal-library membership (v2 Library, #63); see Exercise.inLibrary.
    var inLibrary: Bool = true
    /// Per-tap weight increment for exercises using this gear (nil =
    /// the unit default, 5 lb / 2.5 kg). Unit-agnostic like every
    /// stored number: the value is whatever the user's plates say.
    var weightStep: Double?
    /// Explicit inverse of Exercise.equipment. The relationship ran
    /// inverse-less for months and the store dropped exercise→equipment
    /// rows nondeterministically (#186's field loss; CI's populate-test
    /// flake, still firing after the pre-insert fix) — unidirectional
    /// to-manys are exactly where CoreData integrity is documented to
    /// fray. Not surfaced in UI; exists for store integrity.
    var exercises: [Exercise]? = []

    init(name: String, isBuiltIn: Bool = false) {
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}
