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
            "Current streak: %@",
            comment: "AI tool response for current streak",
            Localization.streakDays(9)
        )
        #expect(response == expected)
    }

    @Test("Streak data tool pluralizes a single-day streak instead of emitting '1 days'")
    func streakDataToolPluralizesSingleDay() async throws {
        let suiteName = "AIPedometerTests.StreakTool.Singular.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.sharedStepData = SharedStepData(
            todaySteps: 8_500,
            goalSteps: 8_000,
            goalProgress: 1.06,
            currentStreak: 1,
            lastUpdated: .now,
            weeklySteps: [8_500]
        )

        let tool = StreakDataTool(suiteName: suiteName)
        let response = try await tool.call(arguments: StreakDataTool.Arguments())

        let expected = Localization.format(
            "Current streak: %@",
            comment: "AI tool response for current streak",
            Localization.streakDays(1)
        )
        #expect(response == expected)
        #expect(!response.contains("1 days"))
        #expect(!response.contains("1 dias"))
    }

    @Test("Streak data tool normalizes stale snapshots across midnight")
    func streakDataToolNormalizesStaleSnapshot() async throws {
        let suiteName = "AIPedometerTests.StreakTool.Stale.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.sharedStepData = SharedStepData(
            todaySteps: 2_000,
            goalSteps: 10_000,
            goalProgress: 0.2,
            currentStreak: 5,
            lastUpdated: Date.now.addingTimeInterval(-86_400 * 2),
            weeklySteps: [2_000]
        )

        let tool = StreakDataTool(suiteName: suiteName)
        let response = try await tool.call(arguments: StreakDataTool.Arguments())

        let expected = Localization.format(
            "Current streak: %@",
            comment: "AI tool response for current streak",
            Localization.streakDays(0)
        )
        #expect(response == expected)
    }
}
