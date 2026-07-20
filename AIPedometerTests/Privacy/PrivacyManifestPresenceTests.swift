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

    @Test("Info.plist supports every iPhone and iPad interface orientation")
    func infoPlistSupportsEveryInterfaceOrientation() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let infoURL = repoRoot.appendingPathComponent("AIPedometer/Resources/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let expectedOrientations: Set<String> = [
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight"
        ]

        let phoneOrientations = Set(plist["UISupportedInterfaceOrientations"] as? [String] ?? [])
        let padOrientations = Set(plist["UISupportedInterfaceOrientations~ipad"] as? [String] ?? [])

        #expect(phoneOrientations == expectedOrientations)
        #expect(padOrientations == expectedOrientations)
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
            let type = entry["NSPrivacyCollectedDataType"] as? String
            return type == "NSPrivacyCollectedDataTypePreciseLocation"
                || type == "NSPrivacyCollectedDataTypeCoarseLocation"
        }

        #expect(hasLocation == false)
    }

    @Test("Privacy manifests declare no collected data when production health egress is absent")
    func privacyManifestsDeclareNoCollectedData() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let manifestPaths = [
            "AIPedometer/Resources/PrivacyInfo.xcprivacy",
            "AIPedometerWatch/Resources/PrivacyInfo.xcprivacy",
            "AIPedometerWidgets/Resources/PrivacyInfo.xcprivacy"
        ]

        for path in manifestPaths {
            let manifestURL = repoRoot.appendingPathComponent(path)
            let data = try Data(contentsOf: manifestURL)
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            let collectedTypes = plist?["NSPrivacyCollectedDataTypes"] as? [[String: Any]]

            #expect(collectedTypes != nil, "\(path) should declare NSPrivacyCollectedDataTypes")
            #expect(collectedTypes?.isEmpty == true, "\(path) should not declare on-device Health/Fitness use as collected data")
        }
    }

    @Test("Privacy manifests declare only valid required-reason API categories")
    func privacyManifestsDeclareOnlyValidRequiredReasonAPIs() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let manifestPaths = [
            "AIPedometer/Resources/PrivacyInfo.xcprivacy",
            "AIPedometerWatch/Resources/PrivacyInfo.xcprivacy",
            "AIPedometerWidgets/Resources/PrivacyInfo.xcprivacy"
        ]
        let validCategories: Set<String> = [
            "NSPrivacyAccessedAPICategoryFileTimestamp",
            "NSPrivacyAccessedAPICategorySystemBootTime",
            "NSPrivacyAccessedAPICategoryDiskSpace",
            "NSPrivacyAccessedAPICategoryActiveKeyboards",
            "NSPrivacyAccessedAPICategoryUserDefaults"
        ]

        for path in manifestPaths {
            let manifestURL = repoRoot.appendingPathComponent(path)
            let data = try Data(contentsOf: manifestURL)
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            let accessedTypes = plist?["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []

            for entry in accessedTypes {
                let category = try #require(entry["NSPrivacyAccessedAPIType"] as? String)
                #expect(validCategories.contains(category), "\(path) contains invalid required-reason category \(category)")
            }
        }
    }
}
