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
    private let sharedUserDefaults: UserDefaults?

    private var lastNotificationDate: Date?
    private var notificationCountToday = 0
    @ObservationIgnored private var isResumingSuspendedReminder = false
    @ObservationIgnored private var inFlightMotivationalReminder: (hour: Int, minute: Int, task: Task<Bool, Never>)?

    private let maxNotificationsPerDay = 3

    init(
        foundationModelsService: any FoundationModelsServiceProtocol,
        healthKitService: any HealthKitServiceProtocol,
        goalService: any GoalServiceProtocol,
        notificationCenter: any NotificationScheduling = UNUserNotificationCenter.current(),
        userDefaults: UserDefaults = .standard,
        sharedUserDefaults: UserDefaults? = .sharedAppGroup
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

    /// Launch, foreground, Settings and the user's toggle can all ask for the same reminder while one is
    /// being generated; they share that generation instead of running the model again.
    @discardableResult
    func scheduleMotivationalReminder(at hour: Int, minute: Int) async -> Bool {
        if let inFlight = inFlightMotivationalReminder, inFlight.hour == hour, inFlight.minute == minute {
            return await inFlight.task.value
        }
        let task = Task { await generateAndScheduleMotivationalReminder(at: hour, minute: minute) }
        inFlightMotivationalReminder = (hour, minute, task)
        let didSchedule = await task.value
        if inFlightMotivationalReminder?.task == task {
            inFlightMotivationalReminder = nil
        }
        return didSchedule
    }

    private func generateAndScheduleMotivationalReminder(at hour: Int, minute: Int) async -> Bool {
        guard foundationModelsService.availability.isAvailable else { return false }

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
            return true
        } catch {
            Loggers.ai.error("ai.motivational_reminder_failed", metadata: [
                "error": error.localizedDescription
            ])
            return false
        }
    }

    /// Brings back a smart reminder whose delivery was suspended without the user asking: on-device AI
    /// was unavailable, or, through 1.0.7, a subscription lapsed. Launch, foreground and Settings all
    /// call this one owner, so two generations never run at once. Nobody asked for this work, so it
    /// only reads the notification permission: it never prompts or alerts, and without permission it
    /// skips the model call and keeps the marker for a later attempt.
    func resumeSuspendedReminderIfNeeded(isNotificationAuthorized: @MainActor () async -> Bool) async {
        guard !isResumingSuspendedReminder else { return }
        isResumingSuspendedReminder = true
        defer { isResumingSuspendedReminder = false }

        let suspendedKey = AppConstants.UserDefaultsKeys.smartRemindersSuspended
        let enabledKey = AppConstants.UserDefaultsKeys.smartRemindersEnabled
        switch SettingsSideEffects.suspendedSmartReminderAction(
            isSuspended: userDefaults.bool(forKey: suspendedKey),
            isEnabled: userDefaults.bool(forKey: enabledKey),
            aiAvailability: foundationModelsService.availability
        ) {
        case .none:
            return
        case .clear:
            userDefaults.removeObject(forKey: suspendedKey)
        case .resume:
            guard await isNotificationAuthorized() else { return }
            let didSchedule = await scheduleMotivationalReminder(
                at: AppConstants.Notifications.defaultSmartReminderHour,
                minute: AppConstants.Notifications.defaultSmartReminderMinute
            )
            guard didSchedule else { return }
            // Generation takes seconds; the user may have turned reminders off meanwhile.
            guard userDefaults.bool(forKey: enabledKey) else {
                cancelAllSmartNotifications()
                userDefaults.removeObject(forKey: suspendedKey)
                return
            }
            userDefaults.removeObject(forKey: suspendedKey)
            Loggers.ai.info("notifications.smart_resumed", metadata: ["reason": "suspension_cleared"])
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

        let content = try validatedContent(from: response)
        // Smart coaching reminders are not genuinely time-critical (medication, security, deliveries
        // are the supported `.timeSensitive` use cases). Use `.active` so the user's Focus modes
        // and notification scheduling remain authoritative.
        content.interruptionLevel = .active

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

        return try validatedContent(from: response)
    }

    private func validatedContent(from response: NotificationContent) throws -> UNMutableNotificationContent {
        let title = response.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = response.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count < 30, !body.isEmpty, body.count < 100 else {
            throw AIServiceError.invalidResponse
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
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
        let sharedData = sharedUserDefaults?.sharedStepData
        let hasFreshSharedData = sharedData?.isStale == false
        if !HealthKitSyncSettings.isEnabled(userDefaults: userDefaults) {
            Loggers.sync.info("healthkit.fetch_skipped", metadata: [
                "reason": "sync_disabled",
                "scope": "smart_notification"
            ])
            guard let sharedData, !sharedData.isStale else {
                throw AIServiceError.generationFailed(underlying: "No recent activity data available")
            }
            let sharedSteps = sharedData.todaySteps
            let distanceKm = settings.activityMode == .steps
                ? Double(sharedSteps) * settings.manualStepLength / 1000
                : nil
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
        let healthKitSteps = today?.steps ?? 0
        let steps = max(healthKitSteps, hasFreshSharedData ? sharedData?.todaySteps ?? 0 : 0)
        let progress = goal > 0 ? Double(steps) / Double(goal) : 0
        let distanceKm: Double?
        if let today, today.distance > 0 {
            distanceKm = today.distance / 1000
        } else if settings.activityMode == .steps {
            distanceKm = Double(steps) * settings.manualStepLength / 1000
        } else {
            distanceKm = nil
        }

        return TodayProgress(
            steps: steps,
            goal: goal,
            progressPercentage: Int(progress * 100),
            distanceKm: distanceKm,
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
        let distanceLine = progress.distanceKm.map {
            "- Distance: \(Formatters.distanceString(meters: $0 * 1_000))\n"
        } ?? ""
        return """
        Generate a personalized notification for a fitness app user:

        Current Progress:
        - \(unitLabelCapitalized) today: \(progress.steps.formatted())
        - Daily goal: \(progress.goal.formatted()) \(unitLabel)
        - Progress: \(progress.progressPercentage)%
        \(distanceLine)- Time of day: \(progress.timeOfDay)

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
    let distanceKm: Double?
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
