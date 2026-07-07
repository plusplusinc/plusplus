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

    init(name: String, isBuiltIn: Bool = false) {
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}
