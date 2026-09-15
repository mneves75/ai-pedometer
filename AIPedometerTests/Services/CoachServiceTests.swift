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

    @Test("Foreground refresh keeps the live session so a follow-up turn keeps its context")
    @MainActor
    func refreshSessionReusesExistingSession() async {
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

        await service.send(message: "turno um")
        // What AppLifecycleCoordinator does on every activation.
        service.refreshSession()
        await service.send(message: "turno dois")

        #expect(builderCalls == 1)
        #expect(sessionA.prompts == ["turno um", "turno dois"])
        #expect(sessionB.prompts.isEmpty)
        #expect(service.messages.count == 4)
    }

    @Test("A replacement session after the model returns clears the conversation it cannot see")
    @MainActor
    func refreshSessionReplacementClearsConversation() async {
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

        await service.send(message: "turno um")
        foundationModels.availability = .unavailable(reason: .modelNotReady)
        service.refreshSession()
        #expect(service.messages.count == 2)

        foundationModels.availability = .available
        service.refreshSession()

        #expect(builderCalls == 2)
        #expect(service.messages.isEmpty)
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
    private(set) var prompts: [String] = []

    init(chunks: [String]) {
        self.chunks = chunks
    }

    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, any Error> {
        prompts.append(prompt)
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
