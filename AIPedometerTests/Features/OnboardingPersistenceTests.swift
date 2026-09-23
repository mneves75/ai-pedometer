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

    @Test("Goal presets sit on the slider grid and include the default goal")
    func goalPresetsMatchTheSlider() {
        let range = OnboardingGoalPreset.sliderRange
        let step = OnboardingGoalPreset.sliderStep
        #expect(!OnboardingGoalPreset.values.isEmpty)
        #expect(OnboardingGoalPreset.values == OnboardingGoalPreset.values.sorted())
        for value in OnboardingGoalPreset.values {
            #expect(range.contains(Double(value)))
            #expect((Double(value) - range.lowerBound).truncatingRemainder(dividingBy: step) == 0)
        }
        #expect(OnboardingGoalPreset.values.contains(AppConstants.defaultDailyGoal))
    }
}
