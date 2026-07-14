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

    // The welcome flow (three screens before the tabs — the one
    // exception to "the timeline IS the onboarding": a first launch
    // gets the idea and the Health ask before the setup steps take
    // over). Shown once per install; the flag is deliberately NOT tied
    // to store contents, so existing installs see the intro once after
    // the update too (and get the Health ask that ships with it).
    static let welcomeSeenKey = "welcomeSeen"

    static var welcomeSeen: Bool {
        UserDefaults.standard.bool(forKey: welcomeSeenKey)
    }

    static func markWelcomeSeen() {
        UserDefaults.standard.set(true, forKey: welcomeSeenKey)
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

    // The populate offer rides Today, not the catalog (#204): Done just
    // raises this flag and dismisses; Today consumes it and asks from an
    // anchored alert. One-shot; the count is computed at ask time.
    static let populateOfferPendingKey = "setupPopulateOfferPending"

    static func requestPopulateOffer() {
        UserDefaults.standard.set(true, forKey: populateOfferPendingKey)
    }

    /// Returns whether an offer was pending, clearing it either way.
    static func consumePopulateOffer() -> Bool {
        let pending = UserDefaults.standard.bool(forKey: populateOfferPendingKey)
        UserDefaults.standard.removeObject(forKey: populateOfferPendingKey)
        return pending
    }
}
