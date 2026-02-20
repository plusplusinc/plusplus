import Foundation
import SwiftData

@Model
final class Equipment {
    var name: String
    var isBuiltIn: Bool

    init(name: String, isBuiltIn: Bool = false) {
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}
