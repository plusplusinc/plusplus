import Foundation
import OSLog
import SwiftData

/// Where the SwiftData store file lives.
///
/// This is an explicit choice rather than a silent fallback because the modes point at *different
/// database files*. A fallback that quietly relocated the store would look like data loss to a
/// user and would be invisible in a crash report.
public enum StorageMode: Sendable {
    /// Shared App Group container with CloudKit sync. What ships.
    ///
    /// Requires the App Group and iCloud entitlements, which on a real device need a paid Apple
    /// Developer Program membership. The simulator does not enforce this, so `.shared` succeeds
    /// there even without provisioning — do not read a working simulator as proof of entitlements.
    case shared
    /// The app's own private container, no sync. For development before entitlements exist.
    case local
    /// Nothing touches disk. Tests and previews.
    case inMemory
}

/// Opens the app's SwiftData store.
///
/// The schema is a parameter rather than a constant here: this type owns *where and how* data is
/// stored, not *what* is stored. Keeping the model list out of it means the storage wiring —
/// App Group path, CloudKit container, mode selection — is settled infrastructure that the data
/// model can evolve independently of.
public enum WorkoutStoreContainer {
    public static let appGroupID = "group.com.plusplusinc.plusplus"
    public static let cloudKitContainerID = "iCloud.com.plusplusinc.plusplus"

    private static let storeName = "PlusPlus"

    private static let logger = Logger(subsystem: "com.plusplusinc.plusplus", category: "storage")

    public static func make(mode: StorageMode, schema: Schema) throws -> ModelContainer {
        let configuration =
            switch mode {
            case .shared:
                ModelConfiguration(
                    storeName,
                    schema: schema,
                    groupContainer: .identifier(appGroupID),
                    cloudKitDatabase: .private(cloudKitContainerID),
                )
            case .local:
                ModelConfiguration(storeName, schema: schema, cloudKitDatabase: .none)
            case .inMemory:
                ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none,
                )
            }

        logger.info("Opening store in \(String(describing: mode), privacy: .public) mode")
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
