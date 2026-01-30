import Foundation

@MainActor
final class HealthKitServiceFallback: HealthKitServiceProtocol, Sendable {
    private let primary: any HealthKitServiceProtocol
    private let demoService: DemoHealthKitService
    private let demoModeStore: DemoModeStore
    private let isHealthDataAvailable: @MainActor () -> Bool
    private let userDefaults: UserDefaults

    private var useFakeDataFallback = false
    private var healthKitUnavailable = false

    init(
        primary: any HealthKitServiceProtocol = HealthKitService(),
        demoModeStore: DemoModeStore,
        calendar: Calendar = .autoupdatingCurrent,
        isHealthDataAvailable: @escaping @MainActor () -> Bool = { HealthKitAuthorization.isAvailable },
        userDefaults: UserDefaults = .standard
    ) {
        self.primary = primary
        self.demoModeStore = demoModeStore
        self.demoService = DemoHealthKitService(calendar: calendar)
        self.isHealthDataAvailable = isHealthDataAvailable
        self.userDefaults = userDefaults
    }

    func requestAuthorization() async throws {
        guard isSyncEnabled else {
            Loggers.health.info("healthkit.authorization_skipped", metadata: ["reason": "sync_disabled"])
            return
        }
        if demoModeStore.shouldUseFakeData {
            _ = enableFakeDataFallback(reason: "fake_data_enabled")
            return
        }
        guard isHealthDataAvailable() else {
            if enableFakeDataFallback(reason: "healthkit_unavailable") { return }
            healthKitUnavailable = true
            Loggers.health.info("healthkit.unavailable_graceful", metadata: ["action": "will_return_empty_data"])
            return
        }

        do {
            try await primary.requestAuthorization()
            useFakeDataFallback = false
            healthKitUnavailable = false
        } catch {
            if enableFakeDataFallback(reason: "authorization_failed", error: error) { return }
            healthKitUnavailable = true
            Loggers.health.info("healthkit.authorization_denied_graceful", metadata: ["action": "will_return_empty_data"])
        }
    }

    func fetchTodaySteps() async throws -> Int {
        try await fetchWithGracefulFallback(emptyValue: 0) {
            try await primary.fetchTodaySteps()
        } fakeData: {
            try await demoService.fetchTodaySteps()
        }
    }

    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int {
        try await fetchWithGracefulFallback(emptyValue: 0) {
            try await primary.fetchSteps(from: startDate, to: endDate)
        } fakeData: {
            try await demoService.fetchSteps(from: startDate, to: endDate)
        }
    }

    func fetchWheelchairPushes(from startDate: Date, to endDate: Date) async throws -> Int {
        try await fetchWithGracefulFallback(emptyValue: 0) {
            try await primary.fetchWheelchairPushes(from: startDate, to: endDate)
        } fakeData: {
            try await demoService.fetchWheelchairPushes(from: startDate, to: endDate)
        }
    }

    func fetchDistance(from startDate: Date, to endDate: Date) async throws -> Double {
        try await fetchWithGracefulFallback(emptyValue: 0.0) {
            try await primary.fetchDistance(from: startDate, to: endDate)
        } fakeData: {
            try await demoService.fetchDistance(from: startDate, to: endDate)
        }
    }

    func fetchFloors(from startDate: Date, to endDate: Date) async throws -> Int {
        try await fetchWithGracefulFallback(emptyValue: 0) {
            try await primary.fetchFloors(from: startDate, to: endDate)
        } fakeData: {
            try await demoService.fetchFloors(from: startDate, to: endDate)
        }
    }

    func fetchDailySummaries(
        days: Int,
        activityMode: ActivityTrackingMode,
        distanceMode: DistanceEstimationMode,
        manualStepLength: Double,
        dailyGoal: Int
    ) async throws -> [DailyStepSummary] {
        try await fetchWithGracefulFallback(emptyValue: []) {
            try await primary.fetchDailySummaries(
                days: days,
                activityMode: activityMode,
                distanceMode: distanceMode,
                manualStepLength: manualStepLength,
                dailyGoal: dailyGoal
            )
        } fakeData: {
            try await demoService.fetchDailySummaries(
                days: days,
                activityMode: activityMode,
                distanceMode: distanceMode,
                manualStepLength: manualStepLength,
                dailyGoal: dailyGoal
            )
        }
    }

    func saveWorkout(_ session: WorkoutSession) async throws {
        guard isSyncEnabled else {
            Loggers.health.info("healthkit.workout_save_skipped", metadata: ["reason": "sync_disabled"])
            return
        }
        if shouldServeFakeData() {
            try await demoService.saveWorkout(session)
            return
        }
        if healthKitUnavailable {
            Loggers.health.info("healthkit.workout_save_skipped", metadata: ["reason": "healthkit_unavailable"])
            return
        }
        try await primary.saveWorkout(session)
    }

    private func fetchWithGracefulFallback<T>(
        emptyValue: T,
        primary: () async throws -> T,
        fakeData: () async throws -> T
    ) async throws -> T {
        if !isSyncEnabled {
            return emptyValue
        }
        if shouldServeFakeData() {
            return try await fakeData()
        }
        if healthKitUnavailable {
            return emptyValue
        }

        do {
            return try await primary()
        } catch let error as HealthKitError {
            return handleHealthKitError(error, emptyValue: emptyValue)
        } catch {
            if enableFakeDataFallback(reason: "query_failed", error: error) {
                return try await fakeData()
            }
            Loggers.health.warning("healthkit.query_failed_graceful", metadata: [
                "error": error.localizedDescription,
                "action": "returning_empty_data"
            ])
            return emptyValue
        }
    }

    private func handleHealthKitError<T>(_ error: HealthKitError, emptyValue: T) -> T {
        switch error {
        case .notAvailable, .authorizationFailed, .noData:
            Loggers.health.info("healthkit.expected_error_graceful", metadata: [
                "error": error.localizedDescription,
                "action": "returning_empty_data"
            ])
            return emptyValue
        case .queryFailed:
            Loggers.health.warning("healthkit.query_failed_graceful", metadata: [
                "error": error.localizedDescription,
                "action": "returning_empty_data"
            ])
            return emptyValue
        }
    }

    private func shouldServeFakeData() -> Bool {
        if useFakeDataFallback { return true }
        if demoModeStore.shouldUseFakeData {
            useFakeDataFallback = true
            Loggers.health.info("healthkit.using_fake_data", metadata: [
                "reason": "fake_data_explicitly_enabled"
            ])
            return true
        }
        return false
    }

    private func enableFakeDataFallback(reason: String, error: (any Error)? = nil) -> Bool {
        guard demoModeStore.shouldUseFakeData else { return false }
        if !useFakeDataFallback {
            var metadata: [String: String] = [
                "reason": reason,
                "fake_data_setting": "\(demoModeStore.useFakeData)"
            ]
            if let error {
                metadata["error"] = error.localizedDescription
            }
            Loggers.health.warning("healthkit.fake_data_fallback_enabled", metadata: metadata)
            useFakeDataFallback = true
        }
        return true
    }

    private var isSyncEnabled: Bool {
        HealthKitSyncSettings.isEnabled(userDefaults: userDefaults)
    }
}
