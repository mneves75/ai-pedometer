import Foundation

struct HealthKitSummaryBuilder {
    let activityMode: ActivityTrackingMode
    let distanceMode: DistanceEstimationMode
    let manualStepLength: Double
    let dailyGoal: Int

    func build(
        date: Date,
        fetchSteps: () async throws -> Int,
        fetchWheelchairPushes: () async throws -> Int,
        fetchDistance: () async throws -> Double,
        fetchFloors: () async throws -> Int
    ) async throws -> DailyStepSummary {
        let activityCount: Int
        switch activityMode {
        case .steps:
            activityCount = try await fetchSteps()
        case .wheelchairPushes:
            activityCount = try await fetchWheelchairPushes()
        }

        let distance = await resolveDistance(
            activityCount: activityCount,
            fetchDistance: fetchDistance
        )

        let floors = await resolveFloors(fetchFloors: fetchFloors)

        return DailyStepSummary(
            date: date,
            steps: activityCount,
            distance: distance,
            floors: floors,
            calories: Double(activityCount) * AppConstants.Metrics.caloriesPerStep,
            goal: dailyGoal
        )
    }

    private func resolveDistance(
        activityCount: Int,
        fetchDistance: () async throws -> Double
    ) async -> Double {
        switch distanceMode {
        case .manual:
            return Double(activityCount) * manualStepLength
        case .automatic:
            do {
                return try await fetchDistance()
            } catch {
                Loggers.health.warning("healthkit.distance_unavailable", metadata: [
                    "error": error.localizedDescription
                ])
                return Double(activityCount) * manualStepLength
            }
        }
    }

    private func resolveFloors(fetchFloors: () async throws -> Int) async -> Int {
        do {
            return try await fetchFloors()
        } catch {
            Loggers.health.warning("healthkit.floors_unavailable", metadata: [
                "error": error.localizedDescription
            ])
            return 0
        }
    }
}
