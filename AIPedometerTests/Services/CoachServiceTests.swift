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

    @Test("Retry rebuilds the coach session before resending")
    @MainActor
    func retryRebuildsSession() async {
        let foundationModels = MockFoundationModelsService()
        foundationModels.availability = .available
        let goalService = GoalService(persistence: PersistenceController(inMemory: true))
        let sessionA = RetrySession(chunks: ["primeira"])
        let sessionB = RetrySession(chunks: ["segunda"])
        var builderCalls = 0

        let service = CoachService(
            foundationModelsService: foundationModels,
            healthKitService: MockHealthKitService(),
            goalService: goalService,
            sessionBuilder: { _, _ in
                defer { builderCalls += 1 }
                return builderCalls == 0 ? sessionA : sessionB
            }
        )

        await service.send(message: "oi")
        await service.retryLastMessage()

        #expect(service.messages.last?.content == "segunda")
        #expect(builderCalls == 2)
    }

    @Test("Unavailable model reason is surfaced to users")
    @MainActor
    func unavailableReasonIsSurfaced() async {
        let foundationModels = MockFoundationModelsService()
        foundationModels.availability = .unavailable(reason: .appleIntelligenceNotEnabled)
        let goalService = GoalService(persistence: PersistenceController(inMemory: true))

        let service = CoachService(
            foundationModelsService: foundationModels,
            healthKitService: MockHealthKitService(),
            goalService: goalService,
            sessionBuilder: { _, _ in nil }
        )

        await service.send(message: "oi")

        #expect(service.messages.last?.content == AIUnavailabilityReason.appleIntelligenceNotEnabled.userFacingMessage)
        if case .modelUnavailable(let reason) = service.lastError {
            #expect(reason == .appleIntelligenceNotEnabled)
        } else {
            Issue.record("Expected modelUnavailable error")
        }
    }
}

@MainActor
private final class RetrySession: CoachSessionProtocol {
    private let chunks: [String]

    init(chunks: [String]) {
        self.chunks = chunks
    }

    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, any Error> {
        let chunks = self.chunks
        return AsyncThrowingStream { continuation in
            Task {
                for chunk in chunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }
}
