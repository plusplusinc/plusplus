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
                        #expect(entry.reps == nil,
                                "\(template.name): \(entry.exercise) is timed but has rep targets")
                        // A timed exercise is prescribed by a clock OR by a
                        // cardio target, since a distance and a pace fix the
                        // duration between them. What it must never be is
                        // blank: an authored template with no target charges
                        // the flat per-set estimate, so "Steady Run" would
                        // advertise five minutes.
                        let prescribesSomething = entry.durationSeconds != nil || !entry.extraTargets.isEmpty
                        #expect(prescribesSomething,
                                "\(template.name): \(entry.exercise) prescribes nothing")
                        // At most TWO of the triad, and every authored
                        // target has to be a metric the exercise actually
                        // tracks — an untracked one is stored invisibly and
                        // silently drops the entry back to the flat 45 s
                        // estimate.
                        let profile = SeedData.builtInProfile(named: entry.exercise)
                        let stated = CardioTargets.triad.filter { metric in
                            metric == .duration ? entry.durationSeconds != nil : entry.extraTargets[metric] != nil
                        }
                        #expect(stated.count <= 2,
                                "\(template.name): \(entry.exercise) states all three of distance, duration and pace")
                        for metric in entry.extraTargets.keys {
                            #expect(profile?.contains(metric) == true,
                                    "\(template.name): \(entry.exercise) targets \(metric.rawValue), which it doesn't track")
                        }
                    } else {
                        #expect(entry.extraTargets.isEmpty,
                                "\(template.name): \(entry.exercise) is weight/reps but carries cardio targets")
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

    @Test("A cardio template lands with its distance, its pace, and its own rest")
    func instantiateCarriesCardioTargets() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        SeedData.loadIfNeeded(context: context)

        let template = try #require(RoutineCatalog.all.first { $0.name == "Quarter Mile Repeats" })
        let routine = template.instantiate(in: context, among: [])

        // Warm-up, the repeats, cool-down.
        #expect(routine.sortedGroups.count == 3)
        let repeats = routine.sortedGroups[1]
        #expect(repeats.sets == 6)
        // The block's own rest, not the routine's — the whole point of a
        // per-block override, and it survives instantiation.
        #expect(repeats.restSecondsOverride == 180)
        #expect(routine.restSeconds == 60)

        let entry = try #require(repeats.sortedExercises.first)
        #expect(entry.target(.distance) == 0.25)
        #expect(entry.target(.pace) == 420)
        // ⚠️ Two of the three, never all three: a stored duration here
        // would outrank nothing but would make the sheet show a value the
        // user never chose, and the derived reading is the honest one.
        #expect(entry.durationSeconds == nil)

        // The warm-up states a clock and nothing else.
        let warmUp = try #require(routine.sortedGroups[0].sortedExercises.first)
        #expect(warmUp.durationSeconds == 600)
        #expect(warmUp.target(.distance) == nil)

        // 600 + 6×105 + 5×180 + 600, plus two block transitions.
        #expect(template.estimatedSeconds == routine.estimatedSeconds)
        #expect(template.estimatedSeconds == 2760)
    }

    @Test("A stale exercise default cannot smuggle a third target into a template")
    func instantiateClearsTheTriadOverAPrefill() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        SeedData.loadIfNeeded(context: context)

        // What editing a Steady Run leaves behind: `bumpExerciseDefaults`
        // writes the last-edited entry's targets onto the EXERCISE (#187),
        // so every later add prefills from them.
        let running = try #require(
            (try? context.fetch(FetchDescriptor<Exercise>()))?.first { $0.name == "Running" }
        )
        running.extraDefaults = [.distance: 3, .pace: 540]

        let template = try #require(RoutineCatalog.all.first { $0.name == "Quarter Mile Repeats" })
        let routine = template.instantiate(in: context, among: [])

        // The warm-up states ten minutes and nothing else. Before the clear
        // ran on duration-only entries it arrived holding distance, pace AND
        // duration, and distance outranks duration in the driver — so a
        // warm-up jog executed as a three-mile set, with the routine's own
        // estimate still reading 600 s and nothing on screen betraying it.
        let warmUp = try #require(routine.sortedGroups[0].sortedExercises.first)
        #expect(warmUp.durationSeconds == 600)
        #expect(warmUp.target(.distance) == nil)
        #expect(warmUp.target(.pace) == nil)
        let warmUpProfile = try #require(warmUp.exercise?.metricProfile)
        #expect(warmUpProfile.driver { warmUp.target($0) } == .duration)

        // And the interval block still keeps its own authored pair.
        let repeats = try #require(routine.sortedGroups[1].sortedExercises.first)
        #expect(repeats.target(.distance) == 0.25)
        #expect(repeats.target(.pace) == 420)
        #expect(repeats.durationSeconds == nil)
    }

    @Test("A steady run's estimate is its distance times its pace")
    func steadyRunEstimate() throws {
        let template = try #require(RoutineCatalog.all.first { $0.name == "Steady Run" })
        // Three miles at 9:00 is twenty-seven minutes. Before the two-of-
        // three law a template could not say this at all.
        #expect(template.estimatedSeconds == 27 * 60)
        #expect(template.estimatedMinutesText == "~25 min")
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
