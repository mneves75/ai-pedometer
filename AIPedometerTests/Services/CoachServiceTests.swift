import Testing

@testable import AIPedometer

@Suite("CoachService Tests")
struct CoachServiceTests {
    @Test("Coach instructions include language directive")
    func coachInstructionsIncludeLanguageDirective() {
        let instruction = CoachService.coachInstructions(
            languageInstruction: "Respond in the user's app language: Portuguese (pt-BR)."
        )

        #expect(instruction.contains("Language:"))
        #expect(instruction.contains("Portuguese"))
        #expect(instruction.contains("pt-BR"))
    }

    @Test("Coach instructions mention HealthKit sync when data is unavailable")
    func coachInstructionsMentionHealthKitSyncWhenUnavailable() {
        let instruction = CoachService.coachInstructions()

        #expect(instruction.contains("HealthKit Sync"))
        #expect(instruction.contains("do not invent"))
    }
}
