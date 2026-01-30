import Foundation
import Testing
import UserNotifications

@testable import AIPedometer

@MainActor
struct SmartNotificationServiceTests {
    @Test("Smart notifications use activity mode unit names")
    func scheduleSmartNotificationUsesActivityModeUnits() async {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(
            ActivityTrackingMode.wheelchairPushes.rawValue,
            forKey: AppConstants.UserDefaultsKeys.activityTrackingMode
        )

        let persistence = PersistenceController(inMemory: true)
        let goalService = GoalService(persistence: persistence)
        goalService.setGoal(5_000)

        let healthKit = MockHealthKitService()
        healthKit.dailySummariesToReturn = [
            DailyStepSummary(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                steps: 1200,
                distance: 1000,
                floors: 0,
                calories: 120,
                goal: 5_000
            )
        ]

        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(NotificationContent(
            title: "Keep going",
            body: "You're making progress!"
        ))

        let notificationCenter = MockNotificationCenter()
        let service = SmartNotificationService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: goalService,
            notificationCenter: notificationCenter,
            userDefaults: testDefaults.defaults
        )

        await service.scheduleSmartNotification()

        let unitName = ActivityTrackingMode.wheelchairPushes.unitName

        #expect(notificationCenter.addedRequests.count == 1)
        #expect(healthKit.lastFetchDailySummariesArgs?.activityMode == .wheelchairPushes)
        #expect(foundationModels.lastPrompt?.contains(unitName.capitalized) ?? false)
    }

    @Test("Smart notifications persist daily limit across launches")
    func smartNotificationsPersistDailyLimit() async {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let persistence = PersistenceController(inMemory: true)
        let goalService = GoalService(persistence: persistence)
        goalService.setGoal(5_000)

        let healthKit = MockHealthKitService()
        healthKit.dailySummariesToReturn = [
            DailyStepSummary(
                date: Date(),
                steps: 1200,
                distance: 1000,
                floors: 0,
                calories: 120,
                goal: 5_000
            )
        ]

        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(NotificationContent(
            title: "Keep going",
            body: "You're making progress!"
        ))

        let notificationCenter = MockNotificationCenter()

        let firstService = SmartNotificationService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: goalService,
            notificationCenter: notificationCenter,
            userDefaults: testDefaults.defaults
        )

        await firstService.scheduleSmartNotification()
        await firstService.scheduleSmartNotification()

        let secondService = SmartNotificationService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: goalService,
            notificationCenter: notificationCenter,
            userDefaults: testDefaults.defaults
        )

        await secondService.scheduleSmartNotification()
        await secondService.scheduleSmartNotification()

        #expect(notificationCenter.addedRequests.count == 3)
        #expect(testDefaults.defaults.integer(forKey: AppConstants.UserDefaultsKeys.smartNotificationCount) == 3)
    }

    @Test("Smart notifications use shared data when HealthKit sync is disabled")
    func smartNotificationsUseSharedDataWhenSyncDisabled() async {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(false, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)
        testDefaults.defaults.sharedStepData = SharedStepData(
            todaySteps: 2222,
            goalSteps: 8_000,
            goalProgress: 0.27775,
            currentStreak: 0,
            lastUpdated: .now,
            weeklySteps: []
        )

        let persistence = PersistenceController(inMemory: true)
        let goalService = GoalService(persistence: persistence)
        goalService.setGoal(8_000)

        let healthKit = MockHealthKitService()
        healthKit.dailySummariesToReturn = [
            DailyStepSummary(
                date: Date(),
                steps: 9999,
                distance: 0,
                floors: 0,
                calories: 0,
                goal: 8_000
            )
        ]

        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(NotificationContent(
            title: "Keep going",
            body: "You're making progress!"
        ))

        let notificationCenter = MockNotificationCenter()
        let service = SmartNotificationService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: goalService,
            notificationCenter: notificationCenter,
            userDefaults: testDefaults.defaults,
            sharedUserDefaults: testDefaults.defaults
        )

        await service.scheduleSmartNotification()

        let formattedSteps = 2222.formatted()

        #expect(notificationCenter.addedRequests.count == 1)
        #expect(healthKit.fetchDailySummariesCallCount == 0)
        #expect(foundationModels.lastPrompt?.contains(formattedSteps) ?? false)
    }

    @Test("Smart notifications skip when shared data is stale and sync is disabled")
    func smartNotificationsSkipWhenSharedDataStale() async {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(false, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)
        testDefaults.defaults.sharedStepData = SharedStepData(
            todaySteps: 4000,
            goalSteps: 8_000,
            goalProgress: 0.5,
            currentStreak: 0,
            lastUpdated: Date().addingTimeInterval(-7200),
            weeklySteps: []
        )

        let persistence = PersistenceController(inMemory: true)
        let goalService = GoalService(persistence: persistence)
        goalService.setGoal(8_000)

        let healthKit = MockHealthKitService()
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(NotificationContent(
            title: "Keep going",
            body: "You're making progress!"
        ))

        let notificationCenter = MockNotificationCenter()
        let service = SmartNotificationService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: goalService,
            notificationCenter: notificationCenter,
            userDefaults: testDefaults.defaults,
            sharedUserDefaults: testDefaults.defaults
        )

        await service.scheduleSmartNotification()

        #expect(notificationCenter.addedRequests.isEmpty)
        #expect(foundationModels.respondCallCount == 0)
    }

    @Test("Smart notification count resets on a new day")
    func smartNotificationsResetOnNewDay() async {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let persistence = PersistenceController(inMemory: true)
        let goalService = GoalService(persistence: persistence)
        goalService.setGoal(5_000)

        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date().addingTimeInterval(-86400)
        testDefaults.defaults.set(
            yesterday.timeIntervalSince1970,
            forKey: AppConstants.UserDefaultsKeys.smartNotificationLastDate
        )
        testDefaults.defaults.set(
            3,
            forKey: AppConstants.UserDefaultsKeys.smartNotificationCount
        )

        let healthKit = MockHealthKitService()
        healthKit.dailySummariesToReturn = [
            DailyStepSummary(
                date: Date(),
                steps: 1200,
                distance: 1000,
                floors: 0,
                calories: 120,
                goal: 5_000
            )
        ]

        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(NotificationContent(
            title: "Fresh start",
            body: "Let's move today!"
        ))

        let notificationCenter = MockNotificationCenter()
        let service = SmartNotificationService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: goalService,
            notificationCenter: notificationCenter,
            userDefaults: testDefaults.defaults
        )

        await service.scheduleSmartNotification()

        #expect(notificationCenter.addedRequests.count == 1)
        #expect(testDefaults.defaults.integer(forKey: AppConstants.UserDefaultsKeys.smartNotificationCount) == 1)
    }
}

@MainActor
final class MockNotificationCenter: NotificationScheduling {
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [String] = []

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }
}
