import Foundation
import SwiftData

@Model
final class Equipment {
    var name: String
    var isBuiltIn: Bool
    /// Personal-library membership (v2 Library, #63); see Exercise.inLibrary.
    var inLibrary: Bool = true

    init(name: String, isBuiltIn: Bool = false) {
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}
