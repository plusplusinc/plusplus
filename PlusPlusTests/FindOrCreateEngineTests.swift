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
        // MINE then CATALOG, and the missing subgroup sits INSIDE its own tier
        // (2026-07-25). Probe Press is built-in and unfavorited, so it belongs
        // to CATALOG, and its missing group follows CATALOG's doable rows.
        #expect(sections.map(\.id) == ["MINE", "CATALOG", "MISSING_CATALOG"])
        // MINE = the favorite + the custom, alphabetical within the tier.
        #expect(sections[0].results.map(\.name) == ["Probe Curl", "Probe Custom Move"])
        #expect(sections[1].results.map(\.name) == ["Probe Squat"])
        #expect(sections[2].kind == .missing(noun: "exercise"))
        #expect(sections[2].results.map(\.name) == ["Probe Press"])
    }

    @Test("Each tier carries its own missing subgroup, not one pooled at the end")
    func missingSplitsPerTier() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)
        // Favoriting the one gear-needing exercise moves it into MINE, so both
        // tiers now hold something the kit can't do.
        let press = try #require(world.exercises.first { $0.name == "Probe Press" })
        press.isFavorite = true
        let bench = try #require(world.equipment.first { $0.name == "Probe Bench" })
        let extra = Exercise(name: "Probe Machine Row", muscleGroup: .back, isBuiltIn: true)
        context.insert(extra)
        extra.equipment = [bench]
        try? context.save()

        let sections = FindOrCreateEngine.sections(
            query: "", scope: .exercises,
            exercises: world.exercises + [extra], equipment: world.equipment,
            routines: world.routines, templates: [], kitNames: world.kitNames
        )
        // Yours-that-need-equipment stays with YOURS; the catalog's stays with
        // the catalog. MINE/CATALOG is the primary split, kit the secondary.
        #expect(sections.map(\.id) == ["MINE", "MISSING_MINE", "CATALOG", "MISSING_CATALOG"])
        #expect(sections[1].results.map(\.name) == ["Probe Press"])
        #expect(sections[3].results.map(\.name) == ["Probe Machine Row"])
    }

    // MARK: - Scope counts

    // The counts the bottom bar paints beside each scope label. They're what
    // replaced the retired All lens: a hit in a scope you aren't looking at
    // has to advertise itself on the control that switches to it. Each scope's
    // surface publishes its own by summing the sections it already built
    // (2026-07-25 — a separate `matchCounts` meant a second ranking pass per
    // keystroke), so the contract under test is that sum. The "an empty query
    // counts nothing" half of the rule lives in the surface, not here.
    private func scopeCount(_ sections: [FindOrCreateEngine.Section]) -> Int {
        sections.reduce(0) { $0 + $1.count }
    }

    @Test("Scope counts cover every scope, doable and missing alike")
    func scopeCountsPerScope() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)

        func count(_ scope: FindScope, templates: [RoutineTemplate] = []) -> Int {
            scopeCount(FindOrCreateEngine.sections(
                query: "Probe", scope: scope,
                exercises: world.exercises, equipment: world.equipment,
                routines: world.routines, templates: templates,
                kitNames: world.kitNames
            ))
        }
        // Exercises counts the missing one too — the count is "results", and a
        // result the kit can't do is still shown (under its disclosure).
        #expect(count(.exercises) == world.exercises.count)
        #expect(count(.kit) == world.equipment.count)
        #expect(count(.routines, templates: [template("Probe Plan")]) == world.routines.count + 1)
    }

    @Test("A query that misses a scope counts it zero")
    func scopeCountZeroForMiss() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)

        func count(_ scope: FindScope) -> Int {
            scopeCount(FindOrCreateEngine.sections(
                query: "Curl", scope: scope,
                exercises: world.exercises, equipment: world.equipment,
                routines: world.routines, templates: [], kitNames: world.kitNames
            ))
        }
        // A zero is what tells the label that switching there is pointless.
        #expect(count(.kit) == 0)
        #expect(count(.exercises) >= 1)
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
            query: "zzzz", scope: .exercises,
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

    // MARK: - Facet filters (2026-07-31)

    /// A catalog exercise as the seeder would create it — real names so
    /// the attribute lookups resolve (Probe fixtures carry no catalog
    /// row, which is itself a case under test: can't-answer drops out).
    private func realBuiltIn(_ name: String, context: ModelContext) throws -> Exercise {
        let def = try #require(SeedData.builtInDefinition(named: name))
        let exercise = Exercise(name: def.name, muscleGroup: def.muscleGroup, exerciseType: def.exerciseType, isBuiltIn: true)
        context.insert(exercise)
        return exercise
    }

    @Test("A muscle facet narrows, and customs still answer it")
    func muscleFacetNarrows() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)

        var filters = CatalogFilterState()
        filters.muscle = .biceps
        let sections = FindOrCreateEngine.sections(
            query: "", scope: .exercises, filters: filters,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines, templates: [], kitNames: world.kitNames
        )
        // Probe Curl files under biceps; the custom (core) and the rest drop.
        #expect(sections.flatMap(\.results).map(\.name) == ["Probe Curl"])

        filters.muscle = .core
        let coreSections = FindOrCreateEngine.sections(
            query: "", scope: .exercises, filters: filters,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines, templates: [], kitNames: world.kitNames
        )
        // The custom answers the muscle chip from its own model data.
        #expect(coreSections.flatMap(\.results).map(\.name) == ["Probe Custom Move"])
    }

    @Test("Attribute facets reach catalog rows; rows that can't answer drop out")
    func attributeFacetsNarrow() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)
        let deadlift = try realBuiltIn("Deadlift", context: context)
        let lateralRaise = try realBuiltIn("Lateral Raise", context: context)
        try? context.save()
        let pool = world.exercises + [deadlift, lateralRaise]

        var filters = CatalogFilterState()
        filters.pattern = .hinge
        let hinge = FindOrCreateEngine.sections(
            query: "", scope: .exercises, filters: filters,
            exercises: pool, equipment: world.equipment,
            routines: world.routines, templates: [], kitNames: world.kitNames
        )
        // Only the real hinge answers; Probe fixtures have no catalog row
        // and drop out under the chip (the can't-classify rule).
        #expect(hinge.flatMap(\.results).map(\.name) == ["Deadlift"])

        filters = CatalogFilterState()
        filters.mechanic = .isolation
        let isolation = FindOrCreateEngine.sections(
            query: "", scope: .exercises, filters: filters,
            exercises: pool, equipment: world.equipment,
            routines: world.routines, templates: [], kitNames: world.kitNames
        )
        #expect(isolation.flatMap(\.results).map(\.name) == ["Lateral Raise"])
    }

    @Test("The kit scope's category facet narrows, and customs drop out")
    func equipmentCategoryFacet() throws {
        let context = ModelContext(try makeContainer())
        let rower = Equipment(name: "Rowing Machine", isBuiltIn: true)
        let barbell = Equipment(name: "Barbell", isBuiltIn: true)
        let custom = Equipment(name: "Probe Widget")
        for item in [rower, barbell, custom] { context.insert(item) }
        try? context.save()

        var filters = CatalogFilterState()
        filters.equipmentCategory = .cardio
        let sections = FindOrCreateEngine.sections(
            query: "", scope: .kit, filters: filters,
            exercises: [], equipment: [rower, barbell, custom],
            routines: [], templates: [], kitNames: []
        )
        #expect(sections.flatMap(\.results).map(\.name) == ["Rowing Machine"])
    }

    @Test("Routine facets: focus derives for hand-built; effort/style drop them")
    func routineFacets() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)
        // Probe Day contains Probe Curl (biceps) → derived focus Upper.
        var filters = CatalogFilterState()
        filters.focus = .upper
        let upper = FindOrCreateEngine.sections(
            query: "", scope: .routines, filters: filters,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines,
            templates: [template("Probe Plan")],  // authored .fullBody — drops
            kitNames: world.kitNames
        )
        #expect(upper.flatMap(\.results).map(\.name) == ["Probe Day"])

        // Under Effort, a hand-built routine can't answer and drops out;
        // the authored template answers.
        filters = CatalogFilterState()
        filters.effort = .moderate
        let moderate = FindOrCreateEngine.sections(
            query: "", scope: .routines, filters: filters,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines,
            templates: [template("Probe Plan")],
            kitNames: world.kitNames
        )
        #expect(moderate.flatMap(\.results).map(\.name) == ["Probe Plan"])
    }

    @Test("Filters compose with the query and keep the missing partition")
    func filtersComposeWithQueryAndMissing() throws {
        let context = ModelContext(try makeContainer())
        let world = makeWorld(context: context)

        var filters = CatalogFilterState()
        filters.muscle = .chest
        let sections = FindOrCreateEngine.sections(
            query: "probe", scope: .exercises, filters: filters,
            exercises: world.exercises, equipment: world.equipment,
            routines: world.routines, templates: [], kitNames: world.kitNames
        )
        // Probe Press (chest) needs gear the kit lacks: it survives the
        // filter AND still lands in its missing group, never hidden.
        let missing = try #require(sections.first { $0.kind == .missing(noun: "exercise") })
        #expect(missing.results.map(\.name) == ["Probe Press"])
        #expect(sections.filter { $0.kind == .results }.flatMap(\.results).isEmpty)
    }

    @Test("Facet bookkeeping: activeFacets, isEmpty, and clear are per scope")
    func facetBookkeeping() {
        var filters = CatalogFilterState()
        filters.muscle = .chest
        filters.pattern = .hinge
        filters.equipmentCategory = .machines
        #expect(filters.activeFacets(for: .exercises).map(\.name) == ["Muscle", "Movement"])
        #expect(filters.activeFacets(for: .kit).map(\.value) == ["Machines"])
        #expect(filters.isEmpty(for: .routines))
        filters.clear(scope: .exercises)
        #expect(filters.isEmpty(for: .exercises))
        // Clearing one scope leaves the others alone.
        #expect(!filters.isEmpty(for: .kit))
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
