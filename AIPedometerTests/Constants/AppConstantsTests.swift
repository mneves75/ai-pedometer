import Foundation
import Testing

@testable import AIPedometer

struct AppConstantsTests {
    @Test
    func metricsStepLengthIsReasonable() {
        let km = AppConstants.Metrics.averageStepLengthKm
        #expect(km > 0.0005)
        #expect(km < 0.001)
    }

    @Test
    func metricsStepLengthKmAndMetersAreConsistent() {
        let km = AppConstants.Metrics.averageStepLengthKm
        let meters = AppConstants.Metrics.averageStepLengthMeters
        #expect(abs(km * 1000 - meters) < 0.001)
    }

    @Test
    func defaultDailyGoalIsReasonable() {
        #expect(AppConstants.defaultDailyGoal >= 5_000)
        #expect(AppConstants.defaultDailyGoal <= 20_000)
    }

    @Test
    func appGroupIDIsValid() {
        #expect(AppConstants.appGroupID.hasPrefix("group."))
        #expect(!AppConstants.appGroupID.isEmpty)
        #expect(AppConstants.appGroupID.contains(AppConstants.bundleIdentifier))
    }

    @Test
    func bundleIdentifierIsValid() {
        #expect(AppConstants.bundleIdentifier.contains("."))
        #expect(!AppConstants.bundleIdentifier.isEmpty)
        #expect(AppConstants.bundleIdentifier == "com.mneves.aipedometer")
    }

    @Test
    func appStoreReviewURLMatchesValidity() {
        if AppConstants.isValidAppStoreID {
            #expect(AppConstants.appStoreReviewURL != nil)
        } else {
            #expect(AppConstants.appStoreReviewURL == nil)
        }
    }

    @Test
    func resolveAppStoreIDReadsFromBundleInfoPlist() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleURL = tempRoot.appendingPathComponent("TestApp.bundle", isDirectory: true)
        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let infoPlistURL = bundleURL.appendingPathComponent("Info.plist")
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.test",
            "AppStoreID": "987654321"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: infoPlistURL, options: .atomic)

        let bundle = try #require(Bundle(url: bundleURL))
        #expect(AppConstants.resolveAppStoreID(bundle: bundle) == "987654321")
    }

    @Test
    func resolveAppStoreIDPrefersEnvironmentValue() {
        let value = AppConstants.resolveAppStoreID(
            bundle: .main,
            environment: ["APP_STORE_ID": "1122334455"]
        )
        #expect(value == "1122334455")
    }

    @Test
    func resolveAppStoreIDTreatsUnexpandedBuildSettingAsPlaceholder() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleURL = tempRoot.appendingPathComponent("TestApp.bundle", isDirectory: true)
        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let infoPlistURL = bundleURL.appendingPathComponent("Info.plist")
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.test",
            "AppStoreID": "$(APP_STORE_ID)"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: infoPlistURL, options: .atomic)

        let bundle = try #require(Bundle(url: bundleURL))
        #expect(AppConstants.resolveAppStoreID(bundle: bundle) == "123456789")
    }

    @Test
    func reviewActionReturnsInAppWhenURLMissing() {
        #expect(AppConstants.reviewAction(appStoreURL: nil) == .requestInApp)
    }

    @Test
    func reviewActionReturnsOpenURLWhenPresent() throws {
        let url = try #require(URL(string: "itms-apps://itunes.apple.com/app/id123456789?action=write-review"))
        #expect(AppConstants.reviewAction(appStoreURL: url) == .openURL(url))
    }
}
