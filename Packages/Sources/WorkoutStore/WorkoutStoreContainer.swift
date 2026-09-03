import Foundation
import OSLog
import SwiftData

/// Where the SwiftData store lives.
///
/// Explicit rather than a silent fallback because the modes point at different databases; a
/// fallback that quietly relocated the store would look like data loss to a user.
public enum StorageMode: Sendable {
    /// The app's own container on disk.
    case local
    /// Nothing touches disk. Tests and previews.
    case inMemory
}

/// Opens the app's SwiftData store.
///
/// The schema is a parameter: this type owns *where and how* data is stored, not *what*, so
/// the storage wiring stays put while the data model evolves.
public enum WorkoutStoreContainer {
    private static let storeName = "PlusPlus"
    private static let logger = Logger(subsystem: "com.plusplusinc.plusplus", category: "storage")

    public static func make(mode: StorageMode, schema: Schema) throws -> ModelContainer {
        let configuration =
            switch mode {
            case .local:
                ModelConfiguration(storeName, schema: schema)
            case .inMemory:
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            }

        logger.info("Opening store in \(String(describing: mode), privacy: .public) mode")
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
