import SwiftData
import Testing
@testable import WorkoutStore

/// A store syncs through CloudKit only when every attribute is optional or has a default, none is
/// unique, and every relationship is optional with an inverse and no deny rule. Sync is not on yet,
/// so nothing
/// else would notice a shape that breaks this until CloudKit refuses the store, and by then the
/// shape has shipped and can't change.
@Suite("CloudKit shapes")
struct CloudKitShapeTests {
    @Test("Every stored shape is one CloudKit can sync")
    func everyShapeSyncs() {
        for version in StoreMigrationPlan.schemas {
            let schema = Schema(versionedSchema: version)
            for entity in schema.entities {
                for problem in Self.problems(in: entity) {
                    Issue.record(
                        """
                        V\(version.versionIdentifier.major) \(entity.name).\(problem): CloudKit \
                        can't sync it. Change it in a version not yet shipped; a shipped one is \
                        frozen, so fix it in a new version.
                        """,
                    )
                }
            }
        }
    }

    /// Each property of the entity CloudKit refuses, as "name: why".
    private static func problems(in entity: Schema.Entity) -> [String] {
        let attributes = entity.attributes
            .filter { !$0.isOptional && $0.defaultValue == nil }
            .map { "\($0.name): neither optional nor with a default" }
        let relationships = entity.relationships.flatMap { relationship -> [String] in
            var found: [String] = []
            if !relationship.isOptional {
                found.append("\(relationship.name): not optional")
            }
            if relationship.inverseName == nil {
                found.append("\(relationship.name): no inverse")
            }
            if relationship.deleteRule == .deny {
                found.append("\(relationship.name): deny delete rule")
            }
            return found
        }
        // `@Attribute(.unique)` lands here as a constraint of one, beside `#Unique`'s.
        let constraints = entity.uniquenessConstraints.map {
            "\($0.joined(separator: ", ")): unique"
        }
        return (attributes + relationships + constraints).sorted()
    }
}
