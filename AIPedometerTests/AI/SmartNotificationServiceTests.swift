import Foundation
import Testing
import UserNotifications

@testable import AIPedometer

@MainActor
struct SmartNotificationServiceTests {
    @Test("Notification distance respects activity mode and available measurement", arguments: [
        (ActivityTrackingMode.wheelchairPushes, false, 0.0, nil as Double?),
        (.wheelchairPushes, true, 0.0, nil),
        (.wheelchairPushes, true, 1250.0, 1250.0),
        (.steps, false, 0.0, 750.0),
        (.steps, true, 0.0, 750.0),
        (.steps, true, 1250.0, 1250.0)
    ])
    func notificationDistanceUsesAvailableEvidence(
        mode: ActivityTrackingMode, syncEnabled: Bool, measuredMeters: Double, expectedMeters: Double?
    ) async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(mode.rawValue, forKey: AppConstants.UserDefaultsKeys.activityTrackingMode)
        testDefaults.defaults.set(syncEnabled, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)
        testDefaults.defaults.set(0.75, forKey: AppConstants.UserDefaultsKeys.manualStepLengthMeters)
        testDefaults.defaults.sharedStepData = SharedStepData(
            todaySteps: 1000, goalSteps: 8000, goalProgress: 0.125,
            currentStreak: 0, lastUpdated: .now, weeklySteps: [], activityMode: mode
        )
        let healthKit = MockHealthKitService()
        healthKit.dailySummariesToReturn = [DailyStepSummary(
            date: .now, steps: 1000, distance: measuredMeters, floors: 0, calories: 0, goal: 8000
        )]
        let models = MockFoundationModelsService()
        models.respondResult = .success(NotificationContent(title: "Keep going", body: "You are making progress!"))
        let notifications = MockNotificationCenter()
        let service = SmartNotificationService(
            foundationModelsService: models, healthKitService: healthKit,
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            notificationCenter: notifications, userDefaults: testDefaults.defaults,
            sharedUserDefaults: testDefaults.defaults
        )

        await service.scheduleSmartNotification()

        let prompt = try #require(models.lastPrompt)
        #expect(notifications.addedRequests.count == 1)
        if let expectedMeters {
            #expect(prompt.contains("- Distance: \(Formatters.distanceString(meters: expectedMeters))"))
        } else {
            #expect(!prompt.contains("- Distance:"))
        }
        #expect(healthKit.fetchDailySummariesCallCount == (syncEnabled ? 1 : 0))
    }

    @Test("Invalid generated notifications neither schedule nor consume daily allowance", arguments: [
        ("", "A short body"), (" \n\t", "A short body"), ("Title", ""), ("Title", " \n\t"),
        (String(repeating: "a", count: 30), "A short body"),
        ("Title", String(repeating: "b", count: 100)),
        (String(repeating: "👩🏽‍🦽", count: 30), "A short body"),
        ("Title", String(repeating: "e\u{301}", count: 100))
    ])
    func invalidNotificationContentIsRejected(title: String, body: String) async {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let models = MockFoundationModelsService()
        models.respondResult = .success(NotificationContent(title: title, body: body))
        let notifications = MockNotificationCenter()
        let service = SmartNotificationService(
            foundationModelsService: models, healthKitService: MockHealthKitService(),
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            notificationCenter: notifications, userDefaults: testDefaults.defaults,
            sharedUserDefaults: testDefaults.defaults
        )

        await service.scheduleSmartNotification()
        let didScheduleReminder = await service.scheduleMotivationalReminder(at: 9, minute: 0)

        #expect(!didScheduleReminder)
        #expect(notifications.addedRequests.isEmpty)
        #expect(testDefaults.defaults.integer(forKey: AppConstants.UserDefaultsKeys.smartNotificationCount) == 0)
        #expect(testDefaults.defaults.object(forKey: AppConstants.UserDefaultsKeys.smartNotificationLastDate) == nil)

        models.respondResult = .success(NotificationContent(title: "Keep going", body: "You are making progress!"))
        for _ in 0..<4 { await service.scheduleSmartNotification() }
        #expect(notifications.addedRequests.count == 3)
        #expect(testDefaults.defaults.integer(forKey: AppConstants.UserDefaultsKeys.smartNotificationCount) == 3)
    }

    @Test("Generated notifications trim whitespace and count Unicode characters", arguments: [
        ("  Keep going\n", "\tYou are making progress!  "),
        (" \(String(repeating: "👩🏽‍🦽", count: 29)) ", " \(String(repeating: "e\u{301}", count: 99)) ")
    ])
    func validNotificationContentIsTrimmed(title: String, body: String) async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let models = MockFoundationModelsService()
        models.respondResult = .success(NotificationContent(title: title, body: body))
        let notifications = MockNotificationCenter()
        let service = SmartNotificationService(
            foundationModelsService: models, healthKitService: MockHealthKitService(),
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            notificationCenter: notifications, userDefaults: testDefaults.defaults,
            sharedUserDefaults: testDefaults.defaults
        )

        await service.scheduleSmartNotification()
        let didScheduleReminder = await service.scheduleMotivationalReminder(at: 9, minute: 0)

        #expect(didScheduleReminder)
        #expect(notifications.addedRequests.count == 2)
        for request in notifications.addedRequests {
            #expect(request.content.title == title.trimmingCharacters(in: .whitespacesAndNewlines))
            #expect(request.content.body == body.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let smartRequest = try #require(notifications.addedRequests.first)
        #expect(smartRequest.content.interruptionLevel == .active)
    }

    @Test("Motivational reminders return false when AI is unavailable")
    func motivationalReminderReturnsFalseWhenAIUnavailable() async {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let persistence = PersistenceController(inMemory: true)
        let goalService = GoalService(persistence: persistence)
        let foundationModels = MockFoundationModelsService()
        foundationModels.availability = .unavailable(reason: .deviceNotEligible)
        let notificationCenter = MockNotificationCenter()

        let service = SmartNotificationService(
            foundationModelsService: foundationModels,
            healthKitService: MockHealthKitService(),
            goalService: goalService,
            notificationCenter: notificationCenter,
            userDefaults: testDefaults.defaults,
            sharedUserDefaults: testDefaults.defaults
        )

        let didSchedule = await service.scheduleMotivationalReminder(at: 9, minute: 0)

        #expect(didSchedule == false)
        #expect(notificationCenter.addedRequests.isEmpty)
    }

    @Test("cancelAllSmartNotifications removes scheduled smart identifiers")
    func cancelAllSmartNotificationsRemovesKnownIdentifiers() {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let persistence = PersistenceController(inMemory: true)
        let goalService = GoalService(persistence: persistence)
        let notificationCenter = MockNotificationCenter()

        let service = SmartNotificationService(
            foundationModelsService: MockFoundationModelsService(),
            healthKitService: MockHealthKitService(),
            goalService: goalService,
            notificationCenter: notificationCenter,
            userDefaults: testDefaults.defaults,
            sharedUserDefaults: testDefaults.defaults
        )

        service.cancelAllSmartNotifications()

        #expect(notificationCenter.removedIdentifiers.contains("ai-smart-notification"))
        #expect(notificationCenter.removedIdentifiers.contains("ai-motivational-9-0"))
    }

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
            userDefaults: testDefaults.defaults,
            sharedUserDefaults: testDefaults.defaults
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
            userDefaults: testDefaults.defaults,
            sharedUserDefaults: testDefaults.defaults
        )

        await firstService.scheduleSmartNotification()
        await firstService.scheduleSmartNotification()

        let secondService = SmartNotificationService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: goalService,
            notificationCenter: notificationCenter,
            userDefaults: testDefaults.defaults,
            sharedUserDefaults: testDefaults.defaults
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

    @Test("Smart notifications prefer fresh shared data when HealthKit is lagging")
    func smartNotificationsPreferFreshSharedDataWhenHealthKitIsLagging() async {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.sharedStepData = SharedStepData(
            todaySteps: 3456,
            goalSteps: 8_000,
            goalProgress: 0.432,
            currentStreak: 0,
            lastUpdated: .now,
            weeklySteps: []
        )

        let persistence = PersistenceController(inMemory: true)
        let goalService = GoalService(persistence: persistence)
        goalService.setGoal(8_000)

        let healthKit = MockHealthKitService()
        healthKit.dailySummariesToReturn = []

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

        #expect(notificationCenter.addedRequests.count == 1)
        #expect(foundationModels.lastPrompt?.contains(3456.formatted()) ?? false)
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
            userDefaults: testDefaults.defaults,
            sharedUserDefaults: testDefaults.defaults
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
