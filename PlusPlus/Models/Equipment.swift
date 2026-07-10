import Foundation
import SwiftData
import PlusPlusKit

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
    /// Suggested tracked-metric profile for exercises on this gear
    /// (flexible metrics), Kit-encoded JSON. nil resolves through
    /// `suggestedProfile`: built-ins fall back to the seed table (a
    /// rower suggests distance/pace/resistance), customs to nil — the
    /// user hasn't said, so new exercises keep the classic default.
    var metricsData: Data?
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

    /// What exercises on this gear typically track — the prefill for new
    /// custom exercises and (for customs) the gate on weight-step config.
    /// nil means "nothing special": plain strength gear.
    var suggestedProfile: MetricProfile? {
        get {
            if let stored = MetricProfile.decode(from: metricsData) { return stored }
            return isBuiltIn ? SeedData.equipmentProfile(named: name) : nil
        }
        set { metricsData = newValue?.encoded() }
    }
}
