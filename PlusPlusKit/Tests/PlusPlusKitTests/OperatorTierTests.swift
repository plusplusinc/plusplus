import Foundation
import Testing
@testable import PlusPlusKit

@Suite("Operator tiering + preview summary")
struct OperatorTierTests {
    // MARK: - Tier table

    @Test("Deleting a persistent entity always previews, at any count")
    func deleteAlwaysPreviews() {
        for entity in [ChangeEntity.routine, .exercise, .library] {
            #expect(ChangeTierPolicy.tier(operation: .delete, entity: entity, affectedCount: 1) == .previewRequired)
        }
    }

    @Test("Dissolving a superset is structural, not destructive")
    func supersetDeleteRidesCountRules() {
        #expect(ChangeTierPolicy.tier(operation: .delete, entity: .superset, affectedCount: 1) == .applyNow)
        #expect(ChangeTierPolicy.tier(operation: .delete, entity: .superset, affectedCount: 4) == .previewRequired)
    }

    @Test("Small non-destructive changes apply immediately")
    func smallChangesApply() {
        #expect(ChangeTierPolicy.tier(operation: .create, entity: .routine, affectedCount: 1) == .applyNow)
        #expect(ChangeTierPolicy.tier(operation: .update, entity: .routine, affectedCount: 1) == .applyNow)
        #expect(ChangeTierPolicy.tier(operation: .update, entity: .exercise, affectedCount: 3) == .applyNow)
    }

    @Test("More than the bulk threshold previews")
    func bulkPreviews() {
        #expect(ChangeTierPolicy.tier(operation: .update, entity: .exercise, affectedCount: 4) == .previewRequired)
        #expect(ChangeTierPolicy.tier(operation: .update, entity: .routine, affectedCount: 12) == .previewRequired)
    }

    @Test("Replacing a library's member list previews even for one library")
    func membershipReplacePreviews() {
        // The whole-list restatement removes whatever it omits — a
        // delete in disguise, so it never auto-applies.
        #expect(ChangeTierPolicy.tier(
            operation: .update, entity: .library, affectedCount: 1,
            replacesMembership: true
        ) == .previewRequired)
        // Deltas (addEquipment/removeEquipment) stay small edits.
        #expect(ChangeTierPolicy.tier(
            operation: .update, entity: .library, affectedCount: 1,
            replacesMembership: false
        ) == .applyNow)
    }

    @Test("Tracking conversion auto-applies only for one entry-free exercise")
    func trackingConversionRules() {
        #expect(ChangeTierPolicy.tier(
            operation: .update, entity: .exercise, affectedCount: 1,
            changesTracking: true, cascadesToEntries: false
        ) == .applyNow)
        #expect(ChangeTierPolicy.tier(
            operation: .update, entity: .exercise, affectedCount: 1,
            changesTracking: true, cascadesToEntries: true
        ) == .previewRequired)
        #expect(ChangeTierPolicy.tier(
            operation: .update, entity: .exercise, affectedCount: 2,
            changesTracking: true
        ) == .previewRequired)
    }

    // MARK: - Preview summary

    @Test("Summary composes verb, count noun, deltas, and samples")
    func summaryComposition() {
        let summary = ChangePreviewSummary.make(
            operation: .update, entity: .exercise, count: 14,
            sampleNames: ["Standing Hamstring Stretch", "Butterfly Stretch", "Neck Stretch"],
            changeDescriptions: ["track by duration · was reps", "30 s per set"]
        )
        #expect(summary.headline == "Changes 14 exercises")
        #expect(summary.lines == [
            "track by duration · was reps",
            "30 s per set",
            "Standing Hamstring Stretch, Butterfly Stretch, Neck Stretch, +11 more",
        ])
    }

    @Test("Singular counts read singular")
    func singularNouns() {
        let summary = ChangePreviewSummary.make(
            operation: .delete, entity: .routine, count: 1,
            sampleNames: ["Push Day"], changeDescriptions: []
        )
        #expect(summary.headline == "Deletes 1 routine")
        #expect(summary.lines == ["Push Day"])
    }

    @Test("Samples line caps at three names and counts the rest")
    func samplesLine() {
        #expect(ChangePreviewSummary.samplesLine(names: ["A", "B", "C", "D"], total: 10) == "A, B, C, +7 more")
        #expect(ChangePreviewSummary.samplesLine(names: ["A"], total: 1) == "A")
        #expect(ChangePreviewSummary.samplesLine(names: [], total: 5) == nil)
    }
}

@Suite("Operator thread policy")
struct OperatorThreadPolicyTests {
    @Test("Token estimation rounds up at ~3 chars per token")
    func tokenEstimation() {
        #expect(OperatorThreadPolicy.estimatedTokens(forCharacters: 0) == 0)
        #expect(OperatorThreadPolicy.estimatedTokens(forCharacters: 1) == 1)
        #expect(OperatorThreadPolicy.estimatedTokens(forCharacters: 3) == 1)
        #expect(OperatorThreadPolicy.estimatedTokens(forCharacters: 4) == 2)
        #expect(OperatorThreadPolicy.estimatedTokens(forCharacters: 300) == 100)
    }

    @Test("Recycle triggers at the window fraction")
    func recycleThreshold() {
        #expect(!OperatorThreadPolicy.shouldRecycle(usedTokens: 2866, contextSize: 4096))
        #expect(OperatorThreadPolicy.shouldRecycle(usedTokens: 2868, contextSize: 4096))
        #expect(OperatorThreadPolicy.shouldRecycle(usedTokens: 100, contextSize: 0))
    }

    @Test("Trimming keeps the largest fitting suffix")
    func trimming() {
        // 300 chars ≈ 100 tokens each; budget 250 tokens keeps two.
        let counts = [300, 300, 300, 300]
        #expect(OperatorThreadPolicy.trimmedRange(entryCharacterCounts: counts, budgetTokens: 250) == 2..<4)
    }

    @Test("Trimming always keeps the final entry, even over budget")
    func trimmingKeepsLastEntry() {
        #expect(OperatorThreadPolicy.trimmedRange(entryCharacterCounts: [9000], budgetTokens: 10) == 0..<1)
        #expect(OperatorThreadPolicy.trimmedRange(entryCharacterCounts: [], budgetTokens: 10) == 0..<0)
    }
}
