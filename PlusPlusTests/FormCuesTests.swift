import Foundation
import Testing
import PlusPlusKit
@testable import PlusPlus

/// The spoken form-cue table's content contract (voice guidance): the
/// catalog and the cues can never drift apart — every built-in speaks,
/// every cue names a real built-in, and every line stays short enough
/// to finish inside the default transition.
struct FormCuesTests {

    /// Full coverage: a voice that speaks for some exercises and goes
    /// silent for others reads as broken, so a new SeedData row fails
    /// here until its cue exists.
    @Test func everyBuiltInExerciseHasACue() {
        let exercises = SeedData.makeBuiltInExercisesForTesting(equipment: [])
        #expect(exercises.count == SeedData.builtInExerciseCount)
        for exercise in exercises {
            #expect(FormCues.line(for: exercise.name) != nil,
                    "\(exercise.name) has no form cue")
        }
    }

    /// No orphans: a renamed or removed catalog exercise must take its
    /// cue along (the RoutineCatalogTests reference rule).
    @Test func everyCueKeyResolvesToACatalogExercise() {
        for name in FormCues.exerciseNames {
            #expect(SeedData.builtInDefinition(named: name) != nil,
                    "form cue for unknown exercise \(name)")
        }
    }

    /// Content law: one short spoken sentence, no em dashes (house copy
    /// rules hold even when the copy is heard, not read), sized to end
    /// inside the default 15 s transition.
    @Test func linesAreSpeakableAndInHouseStyle() {
        for name in FormCues.exerciseNames {
            let line = FormCues.line(for: name) ?? ""
            #expect(!line.isEmpty, "\(name): empty cue")
            #expect(line.hasSuffix("."), "\(name): cue should end as a sentence")
            #expect(line.count <= 120, "\(name): cue too long for a transition")
            #expect(!line.contains("\u{2014}"), "\(name): no em dashes in user-facing copy")
        }
    }

    /// Customs stay quiet by design — we can't know the movement behind
    /// a user's name, and a wrong cue is worse than silence.
    @Test func unknownExercisesStayQuiet() {
        #expect(FormCues.line(for: "Probe Custom Movement") == nil)
        #expect(FormCues.line(for: "") == nil)
    }
}
