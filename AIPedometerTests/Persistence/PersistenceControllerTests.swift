import Foundation
import SwiftData
import Testing

@testable import AIPedometer

@MainActor
struct PersistenceControllerTests {
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
