import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// The routine catalog's content contract (#223): templates are static
/// definitions composed strictly from the built-in exercise catalog,
/// so this suite is what keeps catalog content from drifting when
/// SeedData's exercise list changes.
@Suite(.serialized)
struct RoutineCatalogTests {

    @Test func templateNamesAreUnique() {
        let names = RoutineCatalog.all.map { $0.name.lowercased() }
        #expect(Set(names).count == names.count)
    }

    @Test func everyExerciseReferenceResolves() {
        for template in RoutineCatalog.all {
            for entry in template.blocks.flatMap(\.entries) {
                let def = SeedData.builtInDefinition(named: entry.exercise)
                #expect(def != nil, "\(template.name) references unknown exercise \(entry.exercise)")
            }
        }
    }

    @Test func targetsMatchExerciseTypes() {
        for template in RoutineCatalog.all {
            #expect(!template.blocks.isEmpty, "\(template.name) has no blocks")
            for block in template.blocks {
                #expect(block.sets > 0, "\(template.name) has a 0-set block")
                for entry in block.entries {
                    guard let def = SeedData.builtInDefinition(named: entry.exercise) else { continue }
                    if def.exerciseType == .duration {
                        #expect(entry.durationSeconds != nil && entry.reps == nil,
                                "\(template.name): \(entry.exercise) is timed but has rep targets")
                    } else {
                        #expect(entry.reps != nil && entry.durationSeconds == nil,
                                "\(template.name): \(entry.exercise) is weight/reps but has a duration")
                    }
                    if let reps = entry.reps, let upper = entry.repsUpper {
                        #expect(upper > reps, "\(template.name): \(entry.exercise) range is inverted")
                    }
                }
            }
        }
    }

    @Test func derivationsAreSane() {
        for template in RoutineCatalog.all {
            #expect(template.estimatedSeconds > 0)
            #expect(template.totalSets > 0)
            #expect(!template.muscleGroups.isEmpty, "\(template.name) derives no muscles")
            // Every equipment name a template derives must exist in the
            // built-in equipment catalog (gear the user can actually own).
            let catalogEquipment = Set(SeedData.builtInEquipment.map(\.name))
            for name in template.equipmentNames {
                #expect(catalogEquipment.contains(name),
                        "\(template.name) needs \(name), which isn't in the equipment catalog")
            }
        }
    }

    @Test func instantiateBuildsTheRoutine() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        SeedData.loadIfNeeded(context: context)

        let template = RoutineCatalog.all[0]
        let routine = template.instantiate(in: context, among: [])

        #expect(routine.name == template.name)
        #expect(routine.restSeconds == template.restSeconds)
        #expect(routine.sortedGroups.count == template.blocks.count)
        for (group, block) in zip(routine.sortedGroups, template.blocks) {
            #expect(group.sets == block.sets)
            #expect(group.sortedExercises.count == block.entries.count)
            for (routineExercise, entry) in zip(group.sortedExercises, block.entries) {
                #expect(routineExercise.exercise?.name == entry.exercise)
                if let reps = entry.reps {
                    #expect(routineExercise.reps == reps)
                    #expect(routineExercise.repsUpper == entry.repsUpper)
                }
                if let seconds = entry.durationSeconds {
                    #expect(routineExercise.durationSeconds == seconds)
                }
            }
        }
    }

    @Test func instantiateHandlesSupersetsAndSetOverrides() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        SeedData.loadIfNeeded(context: context)

        // A template with a superset block (reviewer catch: the
        // multi-member path and the sets override were untested).
        let template = try #require(RoutineCatalog.all.first { template in
            template.blocks.contains { $0.entries.count > 1 }
        })
        let routine = template.instantiate(in: context, among: [])

        #expect(routine.sortedGroups.count == template.blocks.count)
        for (group, block) in zip(routine.sortedGroups, template.blocks) {
            #expect(group.sets == block.sets)
            #expect(group.sortedExercises.count == block.entries.count)
            #expect(group.isSuperset == (block.entries.count > 1))
            for (routineExercise, entry) in zip(group.sortedExercises, block.entries) {
                #expect(routineExercise.exercise?.name == entry.exercise)
                if let reps = entry.reps {
                    #expect(routineExercise.reps == reps)
                    #expect(routineExercise.repsUpper == entry.repsUpper)
                }
                if let seconds = entry.durationSeconds {
                    #expect(routineExercise.durationSeconds == seconds)
                }
            }
        }
    }

    @Test func reAddingSuffixesTheName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        SeedData.loadIfNeeded(context: context)

        let template = RoutineCatalog.all[0]
        let first = template.instantiate(in: context, among: [])
        let second = template.instantiate(in: context, among: [first])
        #expect(second.name == "\(template.name) 2")
        #expect(first.order == 1)
        #expect(second.order == 0)
    }

    /// On-disk temp store per container — the only real isolation
    /// (see CLAUDE.md Patterns).
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self, RoutineExercise.self, WorkoutSession.self, SetLog.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routinecatalogtests-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
