import Foundation
import Testing

@testable import AIPedometer

@MainActor
struct HealthKitToolTests {
    @Test("HealthKit data tool uses activity units and settings")
    func healthKitDataToolUsesActivityUnits() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(
            ActivityTrackingMode.wheelchairPushes.rawValue,
            forKey: AppConstants.UserDefaultsKeys.activityTrackingMode
        )

        let persistence = PersistenceController(inMemory: true)
        let goalService = GoalService(persistence: persistence)
        goalService.setGoal(7_500)

        let healthKit = MockHealthKitService()
        healthKit.dailySummariesToReturn = [
            DailyStepSummary(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                steps: 2000,
                distance: 1600,
                floors: 0,
                calories: 180,
                goal: 7_500
            )
        ]

        let tool = HealthKitDataTool(
            healthKitService: healthKit,
            goalService: goalService,
            userDefaultsSuiteName: testDefaults.suiteName
        )

        let response = try await tool.call(arguments: .init(days: 7))

        let unitName = ActivityTrackingMode.wheelchairPushes.unitName

        #expect(healthKit.lastFetchDailySummariesArgs?.activityMode == .wheelchairPushes)
        #expect(healthKit.lastFetchDailySummariesArgs?.days == 7)
        #expect(response.contains("\(unitName.capitalized):"))
        #expect(extractNumber(after: "Goal:", in: response) == 7_500)
        #expect(line(after: "Goal:", in: response)?.contains(unitName) ?? false)
    }

    @Test("HealthKit data tool skips when sync disabled")
    func healthKitDataToolSkipsWhenSyncDisabled() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(false, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)

        let persistence = PersistenceController(inMemory: true)
        let goalService = GoalService(persistence: persistence)
        goalService.setGoal(7_500)

        let healthKit = MockHealthKitService()
        healthKit.dailySummariesToReturn = [
            DailyStepSummary(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                steps: 2000,
                distance: 1600,
                floors: 0,
                calories: 180,
                goal: 7_500
            )
        ]

        let tool = HealthKitDataTool(
            healthKitService: healthKit,
            goalService: goalService,
            userDefaultsSuiteName: testDefaults.suiteName
        )

        let response = try await tool.call(arguments: .init(days: 7))
        let title = String(
            localized: "HealthKit Sync is Off",
            comment: "AI tool response title when HealthKit sync is disabled"
        )

        #expect(healthKit.lastFetchDailySummariesArgs == nil)
        #expect(response.contains(title))
    }

    @Test("Goal data tool returns goal with activity unit")
    func goalDataToolUsesActivityUnits() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(
            ActivityTrackingMode.wheelchairPushes.rawValue,
            forKey: AppConstants.UserDefaultsKeys.activityTrackingMode
        )

        let persistence = PersistenceController(inMemory: true)
        let goalService = GoalService(persistence: persistence)
        goalService.setGoal(3_000)

        let tool = GoalDataTool(goalService: goalService, userDefaultsSuiteName: testDefaults.suiteName)
        let response = try await tool.call(arguments: .init())

        let unitName = ActivityTrackingMode.wheelchairPushes.unitName

        #expect(extractNumber(after: "Current daily goal:", in: response) == 3_000)
        #expect(response.contains(unitName))
    }
}

private func line(after prefix: String, in response: String) -> String? {
    response.split(separator: "\n").first { $0.hasPrefix(prefix) }.map(String.init)
}

private func extractNumber(after prefix: String, in response: String) -> Int? {
    guard let line = line(after: prefix, in: response) else { return nil }
    let digits = line.filter(\.isNumber)
    return Int(digits)
}
