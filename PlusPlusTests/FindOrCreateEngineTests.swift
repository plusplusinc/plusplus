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
        #expect(sections.map(\.title) == ["MINE", "CATALOG"])
        // MINE = the favorite + the custom, alphabetical within the tier.
        #expect(sections[0].results.map(\.name) == ["Probe Curl", "Probe Custom Move"])
        #expect(sections[1].results.map(\.name) == ["Probe Press", "Probe Squat"])
    }

    @Test("All scope caps each section at three and counts the fold")
    func allScopeCaps() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)

        let sections = FindOrCreateEngine.sections(
            query: "", scope: .all,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines, templates: [template("Probe Plan A"), template("Probe Plan B")],
            kitNames: world.kitNames
        )
        #expect(sections.map(\.title) == ["ROUTINES", "EXERCISES", "EQUIPMENT"])
        let routines = sections[0]
        // 1 user routine + 2 templates = 3, capped without a fold.
        #expect(routines.count == 3)
        #expect(routines.moreCount == 0)
        // The user's routine floats above both templates.
        #expect(routines.results.first?.name == "Probe Day")
        let exercises = sections[1]
        #expect(exercises.count == 4)
        #expect(exercises.results.count == 3)
        #expect(exercises.moreCount == 1)
        #expect(exercises.scopeTarget == .exercises)
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
}
