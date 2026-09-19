import Testing

@testable import AIPedometer

struct OnboardingPersistenceTests {
    @Test("Successful goal persistence allows onboarding to finish")
    func successfulPersistenceAllowsCompletion() {
        #expect(OnboardingGoalPersistenceAction(didPersistGoal: true) == .complete)
    }

    @Test("Failed goal persistence keeps onboarding open")
    func failedPersistencePreventsCompletion() {
        #expect(OnboardingGoalPersistenceAction(didPersistGoal: false) == .showSaveError)
    }
}
