import Foundation

@MainActor
final class DemoHealthKitService: HealthKitServiceProtocol, Sendable {
    private let calendar: Calendar
    private let now: () -> Date
    private let weekdayMultipliers: [Double] = [0.65, 0.8, 0.95, 1.1, 1.25, 1.05, 0.75]

    init(
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = { .now }
    ) {
        self.calendar = calendar
        self.now = now
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
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let activityCount: Int
            switch activityMode {
            case .steps:
                activityCount = steps(for: date, dailyGoal: dailyGoal)
            case .wheelchairPushes:
                activityCount = Int(Double(steps(for: date, dailyGoal: dailyGoal)) * 0.9)
            }

            let distance: Double
            switch distanceMode {
            case .automatic:
                distance = Double(activityCount) * AppConstants.Metrics.averageStepLengthMeters
            case .manual:
                distance = Double(activityCount) * manualStepLength
            }

            let floors = max(activityCount / 500, 0)
            return DailyStepSummary(
                date: date,
                steps: activityCount,
                distance: distance,
                floors: floors,
                calories: Double(activityCount) * AppConstants.Metrics.caloriesPerStep,
                goal: dailyGoal
            )
        }
    }

    func saveWorkout(_ session: WorkoutSession) async throws {
        Loggers.health.info("healthkit.demo_workout_ignored", metadata: [
            "start_time": session.startTime.ISO8601Format(),
            "type": session.typeRaw
        ])
    }

    private func steps(for date: Date, dailyGoal: Int) -> Int {
        let weekdayIndex = max(calendar.component(.weekday, from: date) - 1, 0)
        let multiplier = weekdayMultipliers[weekdayIndex % weekdayMultipliers.count]
        let steps = Int((Double(dailyGoal) * multiplier).rounded())
        return max(steps, max(dailyGoal / 4, 500))
    }
}
