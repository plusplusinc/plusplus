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

    /// `migrationPlan` lists every shape a store on disk may hold, `schema` last; nil opens by
    /// lightweight inference alone. The app opens `.local` through `Store.open`, which keeps a
    /// copy of a store while it is renamed.
    public static func make(
        mode: StorageMode,
        schema: Schema,
        migrationPlan: (any SchemaMigrationPlan.Type)? = nil,
    ) throws -> ModelContainer {
        Logger.storage.info("Opening store in \(String(describing: mode), privacy: .public) mode")
        switch mode {
        case .local:
            return try make(
                at: localURL(schema: schema),
                schema: schema,
                migrationPlan: migrationPlan,
            )
        case .inMemory:
            return try ModelContainer(
                for: schema,
                migrationPlan: migrationPlan,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true),
            )
        }
    }

    /// Where `.local` mode keeps the store's file.
    static func localURL(schema: Schema) -> URL {
        ModelConfiguration(storeName, schema: schema).url
    }

    /// Opens the store in the file at `url`, configured as `.local` mode's. Core Data makes the
    /// folder when a new install has none.
    static func make(
        at url: URL,
        schema: Schema,
        migrationPlan: (any SchemaMigrationPlan.Type)?,
    ) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: migrationPlan,
            configurations: ModelConfiguration(storeName, schema: schema, url: url),
        )
    }
}
