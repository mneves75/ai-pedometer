import Foundation
import Testing

@MainActor
struct PrivacyManifestPresenceTests {
    @Test("Privacy manifests exist for all targets")
    func privacyManifestsExistForAllTargets() {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let expectedPaths = [
            "AIPedometer/Resources/PrivacyInfo.xcprivacy",
            "AIPedometerWatch/Resources/PrivacyInfo.xcprivacy",
            "AIPedometerWidgets/Resources/PrivacyInfo.xcprivacy"
        ]

        for path in expectedPaths {
            let url = repoRoot.appendingPathComponent(path)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("Info.plist does not declare location usage when location APIs are unused")
    func infoPlistDoesNotDeclareLocation() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let infoURL = repoRoot.appendingPathComponent("AIPedometer/Resources/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

        #expect(plist?["NSLocationWhenInUseUsageDescription"] == nil)
    }

    @Test("Privacy manifest does not claim location collection without location APIs")
    func privacyManifestDoesNotClaimLocation() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let manifestURL = repoRoot.appendingPathComponent("AIPedometer/Resources/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: manifestURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let collectedTypes = plist?["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? []
        let hasLocation = collectedTypes.contains { entry in
            entry["NSPrivacyCollectedDataType"] as? String == "Location"
        }

        #expect(hasLocation == false)
    }
}
