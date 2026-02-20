import Foundation
import SwiftData

@Model
final class Workout {
    var name: String
    var createdAt: Date
    var order: Int
    @Relationship(deleteRule: .cascade, inverse: \ExerciseGroup.workout)
    var groups: [ExerciseGroup] = []

    init(name: String, order: Int = 0) {
        self.name = name
        self.createdAt = Date()
        self.order = order
    }

    var sortedGroups: [ExerciseGroup] {
        groups.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
    }

    func reindexGroups() {
        for (index, group) in sortedGroups.filter({ !$0.isDeleted }).enumerated() {
            group.order = index
        }
    }
}
