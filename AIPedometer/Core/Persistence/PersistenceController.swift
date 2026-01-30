import Foundation
import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    init(inMemory: Bool = false) {
        let schema = Schema(SchemaV1.models)

        do {
            let configuration: ModelConfiguration
            if inMemory {
                configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            } else {
                let storeURL = try Self.resolveStoreURL()
                configuration = ModelConfiguration(schema: schema, url: storeURL)
            }

            container = try ModelContainer(
                for: schema,
                migrationPlan: ModelMigrationPlan.self,
                configurations: configuration
            )
        } catch {
            Loggers.app.error("persistence.container_init_failed", metadata: ["error": String(describing: error)])
            do {
                let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try ModelContainer(
                    for: schema,
                    migrationPlan: ModelMigrationPlan.self,
                    configurations: fallbackConfig
                )
                Loggers.app.warning("persistence.container_fallback_inmemory")
            } catch {
                Loggers.app.error("persistence.container_fallback_failed", metadata: [
                    "error": String(describing: error)
                ])
                fatalError("Failed to create fallback in-memory ModelContainer: \(error)")
            }
        }
    }

    static func resolveStoreURL(
        fileManager: FileManager = .default,
        appGroupID: String = AppConstants.appGroupID
    ) throws -> URL {
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return try storeURL(baseDirectory: containerURL, fileManager: fileManager)
        }
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("default.store")
    }

    static func storeURL(baseDirectory: URL, fileManager: FileManager = .default) throws -> URL {
        let directory = baseDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("default.store")
    }

    static func resetStore(
        fileManager: FileManager = .default,
        appGroupID: String = AppConstants.appGroupID
    ) {
        do {
            let storeURL = try resolveStoreURL(fileManager: fileManager, appGroupID: appGroupID)
            let walURL = storeURL.appendingPathExtension("wal")
            let shmURL = storeURL.appendingPathExtension("shm")
            [storeURL, walURL, shmURL].forEach { url in
                if fileManager.fileExists(atPath: url.path) {
                    do {
                        try fileManager.removeItem(at: url)
                    } catch {
                        Loggers.app.warning("persistence.reset_remove_failed", metadata: [
                            "path": url.path,
                            "error": String(describing: error)
                        ])
                    }
                }
            }
        } catch {
            Loggers.app.warning("persistence.reset_failed", metadata: ["error": String(describing: error)])
        }
    }
}
