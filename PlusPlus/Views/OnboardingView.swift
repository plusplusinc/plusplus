import SwiftUI
import SwiftData
import PlusPlusKit

/// Setup state for the timeline onboarding (Claude Design handoff 2,
/// "setup-as-timeline"): there is no onboarding flow anymore — a fresh
/// install's Today shows three setup steps as timeline entries, gated
/// bottom-up like commits. Equipment is the only step needing a stored
/// flag (its "done" can't be derived — owning nothing is a valid
/// choice, #232); routines and schedules are derived live.
enum SetupState {
    static let equipmentDoneKey = "setupEquipmentDone"
    static let equipmentDoneDateKey = "setupEquipmentDoneDate"

    static var equipmentDone: Bool {
        UserDefaults.standard.bool(forKey: equipmentDoneKey)
    }

    static func markEquipmentDone() {
        UserDefaults.standard.set(true, forKey: equipmentDoneKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: equipmentDoneDateKey)
    }

    static var equipmentDoneDate: Date? {
        let stamp = UserDefaults.standard.double(forKey: equipmentDoneDateKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    // The welcome beat (now ONE screen — the idea and a jumping-off
    // point, no mechanics tour, no up-front Health ask). Shown once per
    // install; the flag is deliberately NOT tied to store contents, so
    // existing installs see the intro once after the update too.
    static let welcomeSeenKey = "welcomeSeen"

    static var welcomeSeen: Bool {
        UserDefaults.standard.bool(forKey: welcomeSeenKey)
    }

    static func markWelcomeSeen() {
        UserDefaults.standard.set(true, forKey: welcomeSeenKey)
    }

    // The Health primer (the contextual ask that replaced the welcome's
    // Health screen): shown ONCE, right before the first workout starts,
    // whether the user connects or skips. Its own flag because HealthKit
    // hides read authorization by design — we can't derive "already
    // asked" from the store, so we remember it ourselves. Deliberately
    // NOT tied to store contents (a re-install re-primes, which is fine:
    // permissions reset with the install too).
    static let healthPrimerShownKey = "healthPrimerShown"

    static var healthPrimerShown: Bool {
        UserDefaults.standard.bool(forKey: healthPrimerShownKey)
    }

    static func markHealthPrimerShown() {
        UserDefaults.standard.set(true, forKey: healthPrimerShownKey)
    }

    /// Installs that already TRAINED on a pre-primer build had Health
    /// decided by the old welcome screen (or the live monitor's ask), so
    /// don't re-prime them: if the primer flag was never written and the
    /// store already holds workout history, treat it as shown.
    ///
    /// Keyed on prior use, NOT `welcomeSeen` — `welcomeSeen` is set the
    /// instant a fresh user taps "Get started", before their first
    /// workout, and this runs at every launch, so gating on it would
    /// mark the primer shown for a brand-new user who merely relaunched
    /// between onboarding and training (the primer would then never
    /// appear). A genuinely fresh install has NO `WorkoutSession` at
    /// first launch, so this no-ops and they meet the primer at their
    /// first workout; a fresh install that has trained once already set
    /// the flag via the primer itself, so `hasWorkoutHistory` is moot.
    static func backfillHealthPrimerForExistingInstalls(hasWorkoutHistory: Bool) {
        guard UserDefaults.standard.object(forKey: healthPrimerShownKey) == nil,
              hasWorkoutHistory
        else { return }
        markHealthPrimerShown()
    }

    // #155 store-reset breadcrumb. Set ONLY when the store could not be
    // opened and was recreated (never a normal migration, which the
    // migration plan handles silently). RootTabView reads it once to tell
    // the user their data was reset and a backup was saved, then clears
    // it. Deliberately NOT tied to store contents.
    static let storeWasResetKey = "storeWasReset"
    static let storeResetBackupPathKey = "storeResetBackupPath"

    static func markStoreReset(backupPath: String?) {
        UserDefaults.standard.set(true, forKey: storeWasResetKey)
        if let backupPath {
            UserDefaults.standard.set(backupPath, forKey: storeResetBackupPathKey)
        } else {
            // No backup was written (e.g. the copy failed on a full disk) —
            // clear any stale path from a prior incident so the notice
            // doesn't promise a backup that isn't there.
            UserDefaults.standard.removeObject(forKey: storeResetBackupPathKey)
        }
    }

    static var storeWasReset: Bool {
        UserDefaults.standard.bool(forKey: storeWasResetKey)
    }

    /// True when a backup folder was actually written (so copy stated a
    /// path). Drives whether the notice mentions the saved backup.
    static var storeResetBackupSaved: Bool {
        UserDefaults.standard.string(forKey: storeResetBackupPathKey) != nil
    }

    static func clearStoreResetFlag() {
        UserDefaults.standard.removeObject(forKey: storeWasResetKey)
        UserDefaults.standard.removeObject(forKey: storeResetBackupPathKey)
    }

    // The populate offer died with the whole-catalog restructure
    // (2026-07-17): the exercise catalog is always fully visible, so
    // there is nothing to populate. Equipment setup just marks done.
}
