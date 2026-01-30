import Foundation
import Testing

@testable import AIPedometer

@Suite("UserDefaults SharedStepData Tests")
@MainActor
struct UserDefaultsSharedStepDataTests {
    @Test("Shared step data round-trips through UserDefaults")
    func sharedStepDataRoundTrip() {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let expected = SharedStepData(
            todaySteps: 5400,
            goalSteps: 10000,
            goalProgress: 0.54,
            currentStreak: 3,
            lastUpdated: Date(timeIntervalSince1970: 1_735_000_000),
            weeklySteps: [5000, 6000, 7000, 8000, 9000, 10000, 11000]
        )

        testDefaults.defaults.sharedStepData = expected
        let actual = testDefaults.defaults.sharedStepData

        #expect(actual?.todaySteps == expected.todaySteps)
        #expect(actual?.goalSteps == expected.goalSteps)
        #expect(actual?.goalProgress == expected.goalProgress)
        #expect(actual?.currentStreak == expected.currentStreak)
        #expect(actual?.lastUpdated == expected.lastUpdated)
        #expect(actual?.weeklySteps == expected.weeklySteps)
    }

    @Test("Shared step data clears when set to nil")
    func sharedStepDataClearsWhenNil() {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        testDefaults.defaults.sharedStepData = SharedStepData(
            todaySteps: 1200,
            goalSteps: 8000,
            goalProgress: 0.15,
            currentStreak: 1,
            lastUpdated: Date(timeIntervalSince1970: 1_735_000_100),
            weeklySteps: [1200]
        )
        testDefaults.defaults.sharedStepData = nil

        #expect(testDefaults.defaults.sharedStepData == nil)
        #expect(testDefaults.defaults.data(forKey: AppConstants.UserDefaultsKeys.sharedStepData) == nil)
    }

    @Test("Shared step data returns nil on decode failure")
    func sharedStepDataReturnsNilOnDecodeFailure() {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        testDefaults.defaults.set(Data("invalid".utf8), forKey: AppConstants.UserDefaultsKeys.sharedStepData)

        #expect(testDefaults.defaults.sharedStepData == nil)
    }
}
