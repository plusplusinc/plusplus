import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// Hidden synonym accounting + behavior (2026-07-31): every table key
/// names a real catalog row (the FormCues orphan-check shape), and the
/// load-bearing lookups actually reach their targets through the same
/// scoring path the surfaces use.
@Suite("Catalog search synonyms")
struct CatalogSearchSynonymsTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("synonyms-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A catalog exercise as the seeder would create it (the name keys
    /// every table lookup).
    private func builtIn(_ name: String) throws -> Exercise {
        let def = try #require(SeedData.builtInDefinition(named: name), "\(name) not in the catalog")
        return Exercise(name: def.name, muscleGroup: def.muscleGroup, exerciseType: def.exerciseType, isBuiltIn: true)
    }

    @Test("Every synonym key names a real catalog row, and no entry is empty")
    func tablesResolve() {
        for (name, terms) in CatalogSearchSynonyms.exercise {
            #expect(SeedData.builtInDefinition(named: name) != nil, "exercise synonym key '\(name)' resolves to nothing")
            #expect(!terms.trimmingCharacters(in: .whitespaces).isEmpty, "'\(name)' carries empty terms")
        }
        let equipmentNames = Set(SeedData.builtInEquipment.map(\.name))
        for (name, terms) in CatalogSearchSynonyms.equipment {
            #expect(equipmentNames.contains(name), "equipment synonym key '\(name)' resolves to nothing")
            #expect(!terms.trimmingCharacters(in: .whitespaces).isEmpty, "'\(name)' carries empty terms")
        }
    }

    @Test("The haystack answers the terms people actually type")
    func haystackReachesSynonyms() throws {
        func matches(_ query: String, _ name: String) throws -> Bool {
            let haystack = try ExerciseFilterState.searchHaystack(builtIn(name))
            return FuzzySearch.score(query: query, candidate: haystack) != nil
        }
        #expect(try matches("rdl", "Romanian Deadlift"))
        #expect(try matches("tgu", "Turkish Get-Up"))
        #expect(try matches("ohp", "Overhead Press"))
        // Derived family terms, not hand rows.
        #expect(try matches("kb", "Kettlebell Swing"))
        #expect(try matches("db", "Dumbbell Row"))
        #expect(try matches("trx", "Suspension Row"))
        // The movement pattern's display name is searchable.
        #expect(try matches("hinge", "Deadlift"))
        #expect(try matches("carry", "Farmer's Carry"))
        // Dave's compound family answers all its names.
        #expect(try matches("squat thrust", "Dumbbell Thruster"))
        #expect(try matches("plank row", "Renegade Row"))
    }

    @Test("Synonyms rank through the engine: 'rdl' surfaces the Romanian Deadlift first")
    func engineRanksSynonymHit() throws {
        let context = ModelContext(try makeContainer())
        let rdl = try builtIn("Romanian Deadlift")
        let bench = try builtIn("Bench Press")
        context.insert(rdl)
        context.insert(bench)
        try? context.save()

        let sections = FindOrCreateEngine.sections(
            query: "rdl", scope: .exercises,
            exercises: [bench, rdl], equipment: [],
            routines: [], templates: [], kitNames: []
        )
        let names = sections.flatMap(\.results).map(\.name)
        #expect(names.first == "Romanian Deadlift")
    }

    @Test("'erg' and 'bike' reach the machines they mean")
    func equipmentSynonymsReach() throws {
        let context = ModelContext(try makeContainer())
        let rower = Equipment(name: "Rowing Machine", isBuiltIn: true)
        let bicycle = Equipment(name: "Bicycle", isBuiltIn: true)
        let treadmill = Equipment(name: "Treadmill", isBuiltIn: true)
        for item in [rower, bicycle, treadmill] { context.insert(item) }
        try? context.save()

        func hits(_ query: String) -> [String] {
            FindOrCreateEngine.sections(
                query: query, scope: .kit,
                exercises: [], equipment: [rower, bicycle, treadmill],
                routines: [], templates: [], kitNames: []
            ).flatMap(\.results).map(\.name)
        }
        #expect(hits("erg").contains("Rowing Machine"))
        #expect(hits("bike").contains("Bicycle"))
    }

    @Test("A synonym match never suppresses the create row")
    func synonymNeverCollides() throws {
        let context = ModelContext(try makeContainer())
        let rdl = try builtIn("Romanian Deadlift")
        context.insert(rdl)
        try? context.save()

        // "rdl" matches the Romanian Deadlift in RESULTS, but the create
        // collision is exact-real-name only: Create "Rdl" stays offered.
        let c = FindOrCreateEngine.collisions(
            query: "rdl",
            exercises: [rdl], equipment: [], routines: [], templates: []
        )
        #expect(!c.exercise)
        // The real name still collides.
        let exact = FindOrCreateEngine.collisions(
            query: "Romanian Deadlift",
            exercises: [rdl], equipment: [], routines: [], templates: []
        )
        #expect(exact.exercise)
    }
}
