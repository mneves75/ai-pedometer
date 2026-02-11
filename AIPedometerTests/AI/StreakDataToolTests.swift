import Foundation
import Testing

@testable import AIPedometer

@MainActor
struct StreakDataToolTests {
    @Test("Streak data tool reads shared step data")
    func streakDataToolReadsSharedStepData() async throws {
        let suiteName = "AIPedometerTests.StreakTool.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.sharedStepData = SharedStepData(
            todaySteps: 1000,
            goalSteps: 8000,
            goalProgress: 0.125,
            currentStreak: 9,
            lastUpdated: .now,
            weeklySteps: [1000, 2000, 3000]
        )

        let tool = StreakDataTool(suiteName: suiteName)
        let response = try await tool.call(arguments: StreakDataTool.Arguments())

        let expected = Localization.format(
            "Current streak: %lld days",
            comment: "AI tool response for current streak",
            Int64(9)
        )
        #expect(response == expected)
    }
}
