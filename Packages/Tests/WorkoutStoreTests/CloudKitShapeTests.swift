import SwiftData
import Testing
@testable import WorkoutStore

/// A store syncs through CloudKit only when every attribute is optional or has a default, none is
/// unique, and every relationship is optional with an inverse. Sync is not on yet, so nothing
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
                        can't sync it. Add a new schema version; a shipped one is frozen.
                        """,
                    )
                }
            }
        }
    }

    /// Each property of the entity CloudKit refuses, as "name: why".
    private static func problems(in entity: Schema.Entity) -> [String] {
        let attributes = entity.attributes.flatMap { attribute -> [String] in
            var found: [String] = []
            if !attribute.isOptional, attribute.defaultValue == nil {
                found.append("\(attribute.name): neither optional nor with a default")
            }
            if attribute.isUnique {
                found.append("\(attribute.name): unique")
            }
            return found
        }
        let relationships = entity.relationships.flatMap { relationship -> [String] in
            var found: [String] = []
            if !relationship.isOptional {
                found.append("\(relationship.name): not optional")
            }
            if relationship.inverseName == nil {
                found.append("\(relationship.name): no inverse")
            }
            if relationship.isUnique {
                found.append("\(relationship.name): unique")
            }
            return found
        }
        // `@Attribute(.unique)` lands here too, as a constraint of one, already named above.
        let constraints = entity.uniquenessConstraints
            .filter { $0.count > 1 || entity.attributesByName[$0[0]]?.isUnique != true }
            .map { "\($0.joined(separator: ", ")): unique (#Unique)" }
        return (attributes + relationships + constraints).sorted()
    }
}
