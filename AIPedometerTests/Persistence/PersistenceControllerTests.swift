import Foundation
import SwiftData
import Testing

@testable import AIPedometer

@MainActor
struct PersistenceControllerTests {
    @Test("0.91 workout store migrates to durable HealthKit export fields")
    func workoutStoreMigratesFromSchemaV1() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("migration.store")
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        do {
            let legacySchema = Schema(SchemaV1.models)
            let legacyContainer = try ModelContainer(
                for: legacySchema,
                configurations: ModelConfiguration(schema: legacySchema, url: storeURL)
            )
            legacyContainer.mainContext.insert(SchemaV1.WorkoutSession(
                typeRaw: WorkoutType.outdoorWalk.rawValue,
                startTime: start,
                endTime: start.addingTimeInterval(600),
                steps: 1_234
            ))
            try legacyContainer.mainContext.save()
        }

        let currentSchema = Schema(SchemaV2.models)
        let migratedContainer = try ModelContainer(
            for: currentSchema,
            migrationPlan: ModelMigrationPlan.self,
            configurations: ModelConfiguration(schema: currentSchema, url: storeURL)
        )
        let workout = try migratedContainer.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first

        #expect(workout?.steps == 1_234)
        #expect(workout?.healthKitExportState == .notRequired)
        #expect(workout?.healthKitExportIdentifier == nil)
    }

    @Test("New completed workout defaults to pending export without losing fields")
    func newWorkoutGetsDurableExportState() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.mainContext
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = WorkoutSession(type: .outdoorWalk, startTime: start, endTime: start.addingTimeInterval(600), steps: 1_234)
        context.insert(workout)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<WorkoutSession>()).first
        #expect(fetched?.steps == 1_234)
        #expect(fetched?.healthKitExportState == .pending)
        #expect(fetched?.healthKitExportFailureCount == 0)
        #expect(fetched?.healthKitExportIdentifier == nil)
    }

    @Test
    @MainActor
    func inMemoryControllerAllowsSavingModels() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.mainContext
        let goal = StepGoal(dailySteps: 9000, startDate: .now)
        context.insert(goal)

        try context.save()

        let descriptor = FetchDescriptor<StepGoal>()
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
    }

    @Test
    func storeURLCreatesApplicationSupportDirectory() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: baseDirectory) }

        let storeURL = try PersistenceController.storeURL(baseDirectory: baseDirectory, fileManager: fileManager)

        #expect(storeURL.lastPathComponent == "default.store")
        #expect(fileManager.fileExists(atPath: storeURL.deletingLastPathComponent().path))
    }

    @Test
    func resolveStoreURLFallsBackToApplicationSupport() throws {
        let fileManager = FileManager.default
        let url = try PersistenceController.resolveStoreURL(
            fileManager: fileManager,
            appGroupID: "invalid.group.identifier"
        )
        #expect(url.lastPathComponent == "default.store")
    }

    @Test
    func resolveStoreURLThrowsWhenSharedContainerIsRequired() {
        let fileManager = FileManager.default
        #expect(throws: (any Error).self) {
            _ = try PersistenceController.resolveStoreURL(
                fileManager: fileManager,
                appGroupID: "invalid.group.identifier",
                requireSharedContainer: true,
                allowAppSupportFallback: false
            )
        }
    }

    @Test
    func removeStoreFilesDeletesSQLiteSidecars() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("default.store")
        for url in PersistenceController.storeFileURLs(for: storeURL) {
            fileManager.createFile(atPath: url.path, contents: Data(), attributes: nil)
            #expect(fileManager.fileExists(atPath: url.path))
        }

        PersistenceController.removeStoreFiles(at: storeURL, fileManager: fileManager)

        for url in PersistenceController.storeFileURLs(for: storeURL) {
            #expect(!fileManager.fileExists(atPath: url.path))
        }
    }
}
