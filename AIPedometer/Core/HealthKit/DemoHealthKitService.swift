import Foundation

@MainActor
final class DemoHealthKitService: HealthKitServiceProtocol, Sendable {
    private let calendar: Calendar
    private let now: () -> Date
    private let weekdayMultipliers: [Double] = [0.65, 0.8, 0.95, 1.1, 1.25, 1.05, 0.75]
    private let isDeterministic: Bool
    private let deterministicSteps: Int = 8_000

    init(
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = { .now },
        isDeterministic: Bool = LaunchConfiguration.isDeterministicDemoDataEnabled()
    ) {
        self.calendar = calendar
        self.now = now
        self.isDeterministic = isDeterministic
    }

    func requestAuthorization() async throws {
        // Demo data requires no authorization.
    }

    func fetchTodaySteps() async throws -> Int {
        let today = calendar.startOfDay(for: now())
        return steps(for: today, dailyGoal: AppConstants.defaultDailyGoal)
    }

    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int {
        guard startDate < endDate else { return 0 }
        var total = 0
        var current = calendar.startOfDay(for: startDate)
        let end = endDate
        while current < end {
            total += steps(for: current, dailyGoal: AppConstants.defaultDailyGoal)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return total
    }

    func fetchWheelchairPushes(from startDate: Date, to endDate: Date) async throws -> Int {
        let steps = try await fetchSteps(from: startDate, to: endDate)
        return Int(Double(steps) * 0.9)
    }

    func fetchDistance(from startDate: Date, to endDate: Date) async throws -> Double {
        let steps = try await fetchSteps(from: startDate, to: endDate)
        return Double(steps) * AppConstants.Metrics.averageStepLengthMeters
    }

    func fetchFloors(from startDate: Date, to endDate: Date) async throws -> Int {
        let steps = try await fetchSteps(from: startDate, to: endDate)
        return max(steps / 500, 0)
    }

    func fetchDailySummaries(
        days: Int,
        activityMode: ActivityTrackingMode,
        distanceMode: DistanceEstimationMode,
        manualStepLength: Double,
        dailyGoal: Int
    ) async throws -> [DailyStepSummary] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: now())
        let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        return try await fetchDailySummaries(
            from: startDay,
            to: now(),
            activityMode: activityMode,
            distanceMode: distanceMode,
            manualStepLength: manualStepLength,
            dailyGoal: dailyGoal
        )
    }

    func fetchDailySummaries(
        from startDate: Date,
        to endDate: Date,
        activityMode: ActivityTrackingMode,
        distanceMode: DistanceEstimationMode,
        manualStepLength: Double,
        dailyGoal: Int
    ) async throws -> [DailyStepSummary] {
        let startDay = calendar.startOfDay(for: startDate)
        guard startDay <= endDate else { return [] }
        let endDay = calendar.startOfDay(for: endDate)

        var summaries: [DailyStepSummary] = []
        var current = startDay
        while current <= endDay {
            let activityCount: Int
            switch activityMode {
            case .steps:
                activityCount = steps(for: current, dailyGoal: dailyGoal)
            case .wheelchairPushes:
                activityCount = Int(Double(steps(for: current, dailyGoal: dailyGoal)) * 0.9)
            }

            let distance: Double
            switch distanceMode {
            case .automatic:
                distance = Double(activityCount) * AppConstants.Metrics.averageStepLengthMeters
            case .manual:
                distance = Double(activityCount) * manualStepLength
            }

            let floors = max(activityCount / 500, 0)
            summaries.append(
                DailyStepSummary(
                    date: current,
                    steps: activityCount,
                    distance: distance,
                    floors: floors,
                    calories: Double(activityCount) * AppConstants.Metrics.caloriesPerStep,
                    goal: dailyGoal
                )
            )

            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return summaries
    }

    func saveWorkout(_ session: WorkoutSession) async throws {
        Loggers.health.info("healthkit.demo_workout_ignored", metadata: [
            "start_time": session.startTime.ISO8601Format(),
            "type": session.typeRaw
        ])
    }

    private func steps(for date: Date, dailyGoal: Int) -> Int {
        if isDeterministic {
            // Deterministic demo data for tests/CI: stable across weekdays and time zones.
            return deterministicSteps
        }
        let weekdayIndex = max(calendar.component(.weekday, from: date) - 1, 0)
        let multiplier = weekdayMultipliers[weekdayIndex % weekdayMultipliers.count]
        let steps = Int((Double(dailyGoal) * multiplier).rounded())
        return max(steps, max(dailyGoal / 4, 500))
    }
}
