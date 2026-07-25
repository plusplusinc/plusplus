import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("FindOrCreateEngine")
struct FindOrCreateEngineTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("findorcreate-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A small world: two gear pieces (one in the kit), four exercises
    /// (one favorite, one custom), one user routine containing Probe Curl.
    private struct World {
        var exercises: [Exercise]
        var equipment: [Equipment]
        var routines: [Routine]
        var kitNames: Set<String>
    }

    private func makeWorld(context: ModelContext) -> World {
        let barbell = Equipment(name: "Probe Barbell", isBuiltIn: true)
        let bench = Equipment(name: "Probe Bench", isBuiltIn: true)
        context.insert(barbell)
        context.insert(bench)

        let press = Exercise(name: "Probe Press", muscleGroup: .chest, isBuiltIn: true)
        let curl = Exercise(name: "Probe Curl", muscleGroup: .biceps, isBuiltIn: true)
        let squat = Exercise(name: "Probe Squat", muscleGroup: .quads, isBuiltIn: true)
        let custom = Exercise(name: "Probe Custom Move", muscleGroup: .core)
        for e in [press, curl, squat, custom] { context.insert(e) }
        press.equipment = [barbell, bench]
        curl.isFavorite = true

        let routine = Routine(name: "Probe Day", order: 0)
        context.insert(routine)
        routine.addExerciseInNewGroup(curl, context: context)
        try? context.save()

        return World(
            exercises: [curl, custom, press, squat],
            equipment: [barbell, bench],
            routines: [routine],
            kitNames: ["Probe Barbell"]
        )
    }

    private func template(_ name: String, contains: [String] = [], summary: String = "Probe summary") -> RoutineTemplate {
        RoutineTemplate(
            name: name,
            summary: summary,
            focus: .fullBody,
            effort: .moderate,
            style: .strength,
            restSeconds: 45,
            blocks: [RoutineTemplate.Block(sets: 3, entries: contains.map { RoutineTemplate.Entry(exercise: $0) })]
        )
    }

    // MARK: - Empty query

    @Test("Empty query shows everything, mine first then alphabetical")
    func emptyQueryShowsEverything() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)

        let sections = FindOrCreateEngine.sections(
            query: "", scope: .exercises,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines, templates: [], kitNames: world.kitNames
        )
        // Doable grouped MINE/CATALOG, then the collapsible missing group:
        // Probe Press needs Probe Bench (not in the kit), so it splits out.
        #expect(sections.map(\.title) == ["MINE", "CATALOG", "MISSING"])
        // MINE = the favorite + the custom, alphabetical within the tier.
        #expect(sections[0].results.map(\.name) == ["Probe Curl", "Probe Custom Move"])
        #expect(sections[1].results.map(\.name) == ["Probe Squat"])
        #expect(sections[2].kind == .missing(noun: "exercise"))
        #expect(sections[2].results.map(\.name) == ["Probe Press"])
    }

    @Test("All scope caps the doable overview and folds the rest")
    func allScopeCaps() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)

        // Five doable routines (1 user + 4 templates) exercise the fold; the
        // bodyweight exercises stay doable, Probe Press splits to its own group.
        let sections = FindOrCreateEngine.sections(
            query: "", scope: .all,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines,
            templates: [template("Probe Plan A"), template("Probe Plan B"),
                        template("Probe Plan C"), template("Probe Plan D")],
            kitNames: world.kitNames
        )
        let routines = try #require(sections.first { $0.title == "ROUTINES" && $0.kind == .results })
        #expect(routines.count == 5)          // full count before the fold
        #expect(routines.results.count == 3)  // capped
        #expect(routines.moreCount == 2)
        #expect(routines.results.first?.name == "Probe Day")  // yours floats up

        let exercisesDoable = try #require(sections.first { $0.title == "EXERCISES" && $0.kind == .results })
        #expect(exercisesDoable.results.map(\.name) == ["Probe Curl", "Probe Custom Move", "Probe Squat"])
        #expect(exercisesDoable.moreCount == 0)
    }

    @Test("All scope: a missing group follows its type with a scope jump")
    func allScopeMissingGroup() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)

        let sections = FindOrCreateEngine.sections(
            query: "", scope: .all,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines, templates: [], kitNames: world.kitNames
        )
        let missing = try #require(sections.first { $0.kind == .missing(noun: "exercise") })
        #expect(missing.count == 1)
        #expect(missing.results.map(\.name) == ["Probe Press"])
        // The group's more-row jumps into the exercises scope, like the
        // doable overview above it.
        #expect(missing.scopeTarget == .exercises)
        // It sits right after the doable EXERCISES section.
        let titles = sections.map(\.id)
        let doableIdx = try #require(titles.firstIndex(of: "EXERCISES"))
        let missingIdx = try #require(titles.firstIndex(of: "MISSING_EXERCISES"))
        #expect(missingIdx == doableIdx + 1)
    }

    // MARK: - Partitions

    @Test("Kit scope: MINE is the active kit, CATALOG the rest")
    func kitPartition() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)

        let sections = FindOrCreateEngine.sections(
            query: "", scope: .kit,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines, templates: [], kitNames: world.kitNames
        )
        #expect(sections.map(\.title) == ["MINE", "CATALOG"])
        #expect(sections[0].results.map(\.name) == ["Probe Barbell"])
        #expect(sections[1].results.map(\.name) == ["Probe Bench"])
    }

    @Test("An added template leaves CATALOG by name")
    func addedTemplateLeavesCatalog() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)

        let sections = FindOrCreateEngine.sections(
            query: "", scope: .routines,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines,
            templates: [template("Probe Day"), template("Probe Plan")],
            kitNames: world.kitNames
        )
        // "Probe Day" the template is shadowed by the routine of the same
        // name; only "Probe Plan" survives as catalog.
        #expect(sections.map(\.title) == ["MINE", "CATALOG"])
        #expect(sections[0].results.map(\.name) == ["Probe Day"])
        #expect(sections[1].results.map(\.name) == ["Probe Plan"])
    }

    @Test("A deleted routine does not shadow a same-named template")
    func deletedRoutineDoesNotShadowTemplate() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)
        // "Probe Day" the routine is deleted (still in the @Query array in
        // the pre-prune window); the same-named template must reappear
        // rather than being shadowed into nothing — else an exact-name
        // query would suppress the create AND show no row (dead end).
        context.delete(world.routines[0])

        let sections = FindOrCreateEngine.sections(
            query: "probe day", scope: .routines,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines,
            templates: [template("Probe Day")],
            kitNames: world.kitNames
        )
        let names = sections.flatMap(\.results).map(\.name)
        #expect(names.contains("Probe Day"))
    }

    // MARK: - Query ranking

    @Test("A query narrows and keeps yours above the catalog")
    func queryRanksMineFirst() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)

        let sections = FindOrCreateEngine.sections(
            query: "probe", scope: .exercises,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines, templates: [], kitNames: world.kitNames
        )
        // Every fixture matches "probe"; the favorite + custom still lead.
        let names = sections.flatMap(\.results).map(\.name)
        #expect(names.first == "Probe Curl")
        #expect(names.count == 4)
    }

    @Test("No match means no sections")
    func noMatches() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)

        let sections = FindOrCreateEngine.sections(
            query: "zzzz", scope: .all,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines, templates: [], kitNames: world.kitNames
        )
        #expect(sections.isEmpty)
    }

    // MARK: - The has-X explainer

    @Test("A routine matched through a contained exercise names the hit")
    func containedMatchExplainsItself() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)

        let sections = FindOrCreateEngine.sections(
            query: "curl", scope: .routines,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines,
            templates: [template("Probe Plan", contains: ["Probe Curl"])],
            kitNames: world.kitNames
        )
        let all = sections.flatMap(\.results)
        // "Probe Day" contains Probe Curl but its name says nothing about
        // curls: the row carries the explainer.
        let routineHit = try #require(all.first { $0.name == "Probe Day" })
        #expect(routineHit.matchedExerciseName == "Probe Curl")
        let templateHit = try #require(all.first { $0.name == "Probe Plan" })
        #expect(templateHit.matchedExerciseName == "Probe Curl")
    }

    @Test("A name match needs no explainer")
    func nameMatchHasNoExplainer() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)

        let sections = FindOrCreateEngine.sections(
            query: "probe day", scope: .routines,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines, templates: [], kitNames: world.kitNames
        )
        let hit = try #require(sections.flatMap(\.results).first)
        #expect(hit.name == "Probe Day")
        #expect(hit.matchedExerciseName == nil)
    }

    // MARK: - Create collisions

    private func collisions(_ query: String, world: World, templates: [RoutineTemplate] = []) -> FindOrCreateEngine.Collisions {
        FindOrCreateEngine.collisions(
            query: query,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines, templates: templates
        )
    }

    @Test("An empty query never collides")
    func emptyQueryNoCollision() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)
        let c = collisions("   ", world: world)
        #expect(!c.exercise && !c.routine && !c.equipment)
    }

    @Test("An exact equipment name collides, case- and space-insensitively")
    func exactEquipmentCollides() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)
        // The screenshot's bug: typing an existing gear name still offered
        // "Add … as equipment".
        #expect(collisions("Probe Barbell", world: world).equipment)
        #expect(collisions("probe barbell", world: world).equipment)
        #expect(collisions("  Probe Barbell  ", world: world).equipment)
        // Only that one type collides — a routine or exercise of the same
        // name is a different thing and still creatable.
        let c = collisions("Probe Barbell", world: world)
        #expect(!c.exercise && !c.routine)
    }

    @Test("A partial name does not collide")
    func partialNameNoCollision() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)
        // "Circus Dumbbell" vs a "Dumbbells" query: near, not exact.
        #expect(!collisions("Probe Bar", world: world).equipment)
        #expect(!collisions("Probe", world: world).exercise)
    }

    @Test("Exact exercise and routine names collide on their own type")
    func exactExerciseAndRoutineCollide() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)
        #expect(collisions("Probe Curl", world: world).exercise)
        #expect(collisions("Probe Day", world: world).routine)
    }

    @Test("A catalog template name collides on the routine type")
    func exactTemplateCollides() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)
        let c = collisions("Probe Plan", world: world, templates: [template("Probe Plan")])
        #expect(c.routine)
    }

    // MARK: - Missing-equipment group

    @Test("An exercise the kit can't do groups under the missing section, not CATALOG")
    func missingExerciseGroups() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)
        // Probe Press needs Probe Bench (not in the kit); the others are
        // bodyweight. It splits into the collapsible group, kept out of the
        // doable MINE/CATALOG groups.
        let sections = FindOrCreateEngine.sections(
            query: "", scope: .exercises,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines, templates: [], kitNames: world.kitNames
        )
        let doable = sections.filter { $0.kind == .results }.flatMap(\.results).map(\.name)
        #expect(!doable.contains("Probe Press"))
        #expect(doable.contains("Probe Curl"))
        let missing = try #require(sections.first { $0.kind == .missing(noun: "exercise") })
        #expect(missing.results.map(\.name) == ["Probe Press"])
    }

    @Test("Result.doable reflects kit availability")
    func resultDoableFlag() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)
        let sections = FindOrCreateEngine.sections(
            query: "", scope: .exercises,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines, templates: [], kitNames: world.kitNames
        )
        let byName = Dictionary(uniqueKeysWithValues: sections.flatMap(\.results).map { ($0.name, $0.doable) })
        #expect(byName["Probe Curl"] == true)
        #expect(byName["Probe Press"] == false)
    }

    @Test("A routine the kit can't do groups under the missing section")
    func missingRoutineGroups() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)
        // A routine built on Probe Press needs Probe Bench; Probe Day (Probe
        // Curl) is bodyweight and stays doable.
        let press = try #require(world.exercises.first { $0.name == "Probe Press" })
        let gymDay = Routine(name: "Probe Gym Day", order: 1)
        context.insert(gymDay)
        gymDay.addExerciseInNewGroup(press, context: context)
        try? context.save()

        let sections = FindOrCreateEngine.sections(
            query: "", scope: .routines,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines + [gymDay], templates: [], kitNames: world.kitNames
        )
        let doable = sections.filter { $0.kind == .results }.flatMap(\.results).map(\.name)
        #expect(doable.contains("Probe Day"))
        #expect(!doable.contains("Probe Gym Day"))
        let missing = try #require(sections.first { $0.kind == .missing(noun: "routine") })
        #expect(missing.results.map(\.name) == ["Probe Gym Day"])
    }
}
