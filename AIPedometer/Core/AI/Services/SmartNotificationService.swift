import Foundation
import FoundationModels
import Observation
import UserNotifications

@MainActor
protocol NotificationScheduling {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: NotificationScheduling {
}

@MainActor
@Observable
final class SmartNotificationService {
    private let foundationModelsService: any FoundationModelsServiceProtocol
    private let healthKitService: any HealthKitServiceProtocol
    private let goalService: any GoalServiceProtocol
    private let notificationCenter: any NotificationScheduling
    private let userDefaults: UserDefaults
    private let sharedUserDefaults: UserDefaults

    private var lastNotificationDate: Date?
    private var notificationCountToday = 0

    private let maxNotificationsPerDay = 3

    init(
        foundationModelsService: any FoundationModelsServiceProtocol,
        healthKitService: any HealthKitServiceProtocol,
        goalService: any GoalServiceProtocol,
        notificationCenter: any NotificationScheduling = UNUserNotificationCenter.current(),
        userDefaults: UserDefaults = .standard,
        sharedUserDefaults: UserDefaults = .shared
    ) {
        self.foundationModelsService = foundationModelsService
        self.healthKitService = healthKitService
        self.goalService = goalService
        self.notificationCenter = notificationCenter
        self.userDefaults = userDefaults
        self.sharedUserDefaults = sharedUserDefaults

        loadPersistedState()
        resetDailyCounterIfNeeded()
    }

    func scheduleSmartNotification() async {
        guard foundationModelsService.availability.isAvailable else { return }
        guard canSendNotification() else { return }

        do {
            let content = try await generateNotificationContent()
            let request = createNotificationRequest(content: content)

            try await notificationCenter.add(request)
            recordNotificationSent()

            Loggers.ai.info("ai.smart_notification_scheduled", metadata: [
                "title": content.title
            ])
        } catch {
            Loggers.ai.error("ai.smart_notification_failed", metadata: [
                "error": error.localizedDescription
            ])
        }
    }

    func scheduleMotivationalReminder(at hour: Int, minute: Int) async {
        guard foundationModelsService.availability.isAvailable else { return }

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        do {
            let content = try await generateMotivationalContent()
            let request = UNNotificationRequest(
                identifier: motivationalReminderIdentifier(hour: hour, minute: minute),
                content: content,
                trigger: trigger
            )

            try await notificationCenter.add(request)

            Loggers.ai.info("ai.motivational_reminder_scheduled", metadata: [
                "hour": "\(hour)",
                "minute": "\(minute)"
            ])
        } catch {
            Loggers.ai.error("ai.motivational_reminder_failed", metadata: [
                "error": error.localizedDescription
            ])
        }
    }

    func cancelAllSmartNotifications() {
        let identifiers = [Self.smartNotificationIdentifier] + motivationalReminderIdentifiers
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static let smartNotificationIdentifier = "ai-smart-notification"
    private static let motivationalReminderPrefix = "ai-motivational"

    private func motivationalReminderIdentifier(hour: Int, minute: Int) -> String {
        "\(Self.motivationalReminderPrefix)-\(hour)-\(minute)"
    }

    private var motivationalReminderIdentifiers: [String] {
        (0..<24).flatMap { hour in
            [0, 15, 30, 45].map { minute in
                motivationalReminderIdentifier(hour: hour, minute: minute)
            }
        }
    }

    private func canSendNotification() -> Bool {
        resetDailyCounterIfNeeded()
        return notificationCountToday < maxNotificationsPerDay
    }

    private func resetDailyCounterIfNeeded() {
        let calendar = Calendar.current
        if let lastDate = lastNotificationDate,
           !calendar.isDateInToday(lastDate) {
            notificationCountToday = 0
            lastNotificationDate = nil
            persistNotificationState()
        }
    }

    private func recordNotificationSent() {
        lastNotificationDate = Date()
        notificationCountToday += 1
        persistNotificationState()
    }

    private func loadPersistedState() {
        let timestamp = userDefaults.double(forKey: AppConstants.UserDefaultsKeys.smartNotificationLastDate)
        if timestamp > 0 {
            lastNotificationDate = Date(timeIntervalSince1970: timestamp)
        }
        notificationCountToday = userDefaults.integer(forKey: AppConstants.UserDefaultsKeys.smartNotificationCount)
    }

    private func persistNotificationState() {
        if let lastNotificationDate {
            userDefaults.set(lastNotificationDate.timeIntervalSince1970, forKey: AppConstants.UserDefaultsKeys.smartNotificationLastDate)
        } else {
            userDefaults.removeObject(forKey: AppConstants.UserDefaultsKeys.smartNotificationLastDate)
        }
        userDefaults.set(notificationCountToday, forKey: AppConstants.UserDefaultsKeys.smartNotificationCount)
    }

    private func generateNotificationContent() async throws -> UNMutableNotificationContent {
        let todayData = try await fetchTodayProgress()
        let prompt = buildNotificationPrompt(progress: todayData)

        let response: NotificationContent = try await foundationModelsService.respond(
            to: prompt,
            as: NotificationContent.self
        )

        let content = UNMutableNotificationContent()
        content.title = response.title
        content.body = response.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        return content
    }

    private func generateMotivationalContent() async throws -> UNMutableNotificationContent {
        let prompt = """
        Generate a short, motivational notification to encourage activity:
        - Title should be catchy and under 30 characters
        - Body should be encouraging and under 100 characters
        - Focus on the benefits of staying active or gentle encouragement
        - Avoid medical advice, diagnoses, or weight-loss promises
        - Keep the tone positive and non-judgmental
        """

        let response: NotificationContent = try await foundationModelsService.respond(
            to: prompt,
            as: NotificationContent.self
        )

        let content = UNMutableNotificationContent()
        content.title = response.title
        content.body = response.body
        content.sound = .default

        return content
    }

    private func createNotificationRequest(content: UNMutableNotificationContent) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: Self.smartNotificationIdentifier,
            content: content,
            trigger: nil
        )
    }

    private func fetchTodayProgress() async throws -> TodayProgress {
        let settings = ActivitySettings.current(userDefaults: userDefaults)
        let goal = goalService.currentGoal
        if !HealthKitSyncSettings.isEnabled(userDefaults: userDefaults) {
            Loggers.sync.info("healthkit.fetch_skipped", metadata: [
                "reason": "sync_disabled",
                "scope": "smart_notification"
            ])
            guard let sharedData = sharedUserDefaults.sharedStepData, !sharedData.isStale else {
                throw AIServiceError.generationFailed(underlying: "No recent activity data available")
            }
            let sharedSteps = sharedData.todaySteps
            let distanceKm = Double(sharedSteps) * settings.manualStepLength / 1000
            let progress = goal > 0 ? Double(sharedSteps) / Double(goal) : 0
            return TodayProgress(
                steps: sharedSteps,
                goal: goal,
                progressPercentage: Int(progress * 100),
                distanceKm: distanceKm,
                timeOfDay: currentTimeOfDay(),
                unitName: settings.activityMode.unitName
            )
        }
        let summaries = try await healthKitService.fetchDailySummaries(
            days: 1,
            activityMode: settings.activityMode,
            distanceMode: settings.distanceMode,
            manualStepLength: settings.manualStepLength,
            dailyGoal: goal
        )

        let today = summaries.first
        let steps = today?.steps ?? 0
        let progress = goal > 0 ? Double(steps) / Double(goal) : 0

        return TodayProgress(
            steps: steps,
            goal: goal,
            progressPercentage: Int(progress * 100),
            distanceKm: (today?.distance ?? 0) / 1000,
            timeOfDay: currentTimeOfDay(),
            unitName: settings.activityMode.unitName
        )
    }

    private func currentTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return L10n.localized("Morning", comment: "Time of day")
        case 12..<17:
            return L10n.localized("Afternoon", comment: "Time of day")
        case 17..<21:
            return L10n.localized("Evening", comment: "Time of day")
        default:
            return L10n.localized("Night", comment: "Time of day")
        }
    }

    private func buildNotificationPrompt(progress: TodayProgress) -> String {
        let unitLabel = progress.unitName
        let unitLabelCapitalized = unitLabel.capitalized
        return """
        Generate a personalized notification for a fitness app user:

        Current Progress:
        - \(unitLabelCapitalized) today: \(progress.steps.formatted())
        - Daily goal: \(progress.goal.formatted()) \(unitLabel)
        - Progress: \(progress.progressPercentage)%
        - Distance: \(progress.distanceKm.formatted(.number.precision(.fractionLength(1)))) km
        - Time of day: \(progress.timeOfDay)

        Requirements:
        - Title: Catchy, under 30 characters
        - Body: Encouraging, personalized to their progress, under 100 characters
        - If progress < 50%, encourage getting started
        - If progress 50-90%, encourage finishing strong
        - If progress >= 90%, celebrate being close to the goal
        - Avoid medical advice or weight-loss promises; keep it supportive
        """
    }
}

private struct TodayProgress {
    let steps: Int
    let goal: Int
    let progressPercentage: Int
    let distanceKm: Double
    let timeOfDay: String
    let unitName: String
}

@Generable
struct NotificationContent: Sendable {
    @Guide(description: "Notification title, catchy and under 30 characters")
    let title: String

    @Guide(description: "Notification body, encouraging and under 100 characters")
    let body: String
}
