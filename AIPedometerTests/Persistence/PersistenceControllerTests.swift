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
}
