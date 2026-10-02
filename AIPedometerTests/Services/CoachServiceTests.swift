import Foundation
import Testing

@testable import AIPedometer

@Suite("CoachService Tests")
struct CoachServiceTests {
    private static let messageHeading = L10n.localized("User message:", comment: "AI Coach prompt heading before the user's own message")

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

    @Test("Retry gives the replacement session the conversation visible before the failed turn")
    @MainActor
    func retryPreservesPriorConversation() async {
        let foundationModels = MockFoundationModelsService()
        foundationModels.availability = .available
        let firstSession = SucceedThenFailSession()
        let replacementSession = RetrySession(chunks: ["The second option is now easier."])
        var builderCalls = 0
        let service = CoachService(
            foundationModelsService: foundationModels,
            healthKitService: MockHealthKitService(),
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            sessionBuilder: { _, _ in
                defer { builderCalls += 1 }
                return builderCalls == 0 ? firstSession : replacementSession
            }
        )
        await service.send(message: "Give me two walking options")
        await service.send(message: "Make the second option easier")
        #expect(service.lastError != nil)
        await service.retryLastMessage()

        let retryPrompt = replacementSession.prompts.first ?? ""
        #expect(retryPrompt.contains("Give me two walking options"))
        #expect(retryPrompt.contains("Option one: a flat park. Option two: a steep hill."))
        #expect(retryPrompt.hasSuffix("Make the second option easier"))
        #expect(service.messages.count == 4)
        #expect(service.lastError == nil)
        await service.send(message: "What about option one?")
        #expect(replacementSession.prompts.last == "What about option one?")
    }

    @Test("Retry limits large completed history while retaining recent quoted context", arguments: ["walking ", "ação 👩🏽‍💻 \"\n"])
    @MainActor
    func retryBoundsLargeCompletedConversation(repeatedText: String) async {
        let original = ContextWindowSession(successfulCalls: 3, response: "RECENT OPTION: " + String(repeating: repeatedText, count: 2_000))
        let replacement = ContextWindowSession(successfulCalls: .max, maximumReplayBytes: 2_048, response: "Recovered")
        var builds = 0
        let service = CoachService(
            foundationModelsService: MockFoundationModelsService(),
            healthKitService: MockHealthKitService(),
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            sessionBuilder: { _, _ in
                defer { builds += 1 }
                return builds == 0 ? original : replacement
            }
        )
        for index in 1...3 { await service.send(message: "Question \(index)") }
        await service.send(message: "Make the recent option easier")
        #expect(service.lastError != nil)
        await service.retryLastMessage()
        #expect(service.lastError == nil)
        #expect(service.messages.count == 8)
        #expect(service.messages.first?.content == "Question 1")
        let prompt = replacement.prompts.first ?? ""
        #expect(ContextWindowSession.replayBytes(in: prompt) <= 2_048)
        #expect(prompt.contains("RECENT OPTION:"))
        #expect(prompt.contains(Self.messageHeading))
        #expect(prompt.hasSuffix("Make the recent option easier"))
    }

    @Test("Repeated context-limit retries shrink replay until the replacement request fits")
    @MainActor
    func retryReducesReplayAfterRepeatedContextOverflow() async {
        let original = ContextWindowSession(successfulCalls: 1, response: "RECENT OPTION: " + String(repeating: "walk ", count: 2_000))
        let replacement = ContextWindowSession(successfulCalls: .max, maximumReplayBytes: 96, response: "Recovered")
        var builds = 0
        let service = CoachService(
            foundationModelsService: MockFoundationModelsService(),
            healthKitService: MockHealthKitService(),
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            sessionBuilder: { _, _ in
                defer { builds += 1 }
                return builds == 0 ? original : replacement
            }
        )
        await service.send(message: "Suggest a walking option")
        await service.send(message: "Make it easier")
        for _ in 0..<8 {
            guard service.lastError != nil else { break }
            await service.retryLastMessage()
        }
        #expect(service.lastError == nil)
        #expect(service.messages.count == 4)
        let sizes = replacement.prompts.map { ContextWindowSession.replayBytes(in: $0) }
        #expect(sizes.count > 1)
        #expect(zip(sizes, sizes.dropFirst()).allSatisfy { $0.0 > $0.1 })
        #expect(replacement.prompts.allSatisfy { $0.hasSuffix("Make it easier") })
        #expect(replacement.prompts.allSatisfy { $0.contains(Self.messageHeading) })
    }

    @Test("An exhausted replay stays empty across failures until a new question starts")
    @MainActor
    func retryDoesNotRestoreExhaustedContext() async {
        let original = ContextWindowSession(successfulCalls: 1, response: String(repeating: "Recent walking context ", count: 200))
        let replacement = ContextWindowSession(successfulCalls: 0, response: "Unused")
        var builds = 0
        let service = CoachService(
            foundationModelsService: MockFoundationModelsService(),
            healthKitService: MockHealthKitService(),
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            sessionBuilder: { _, _ in
                defer { builds += 1 }
                return builds == 0 ? original : replacement
            }
        )
        await service.send(message: "Suggest a walking option")
        await service.send(message: "Make it easier")
        for _ in 0..<12 { await service.retryLastMessage() }
        let sizes = replacement.prompts.map { ContextWindowSession.replayBytes(in: $0) }
        guard let exhausted = sizes.firstIndex(of: 0) else {
            Issue.record("Replay was never exhausted")
            return
        }
        #expect(sizes[exhausted...].allSatisfy { $0 == 0 })
        #expect(service.lastError != nil)
        #expect(service.messages.first?.content == "Suggest a walking option")
        await service.send(message: "Start a different question")
        await service.retryLastMessage()
        #expect(ContextWindowSession.replayBytes(in: replacement.prompts.last ?? "") > 0)
        #expect(replacement.prompts.last?.hasSuffix("Start a different question") == true)
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
        #expect(sessionA.prompts.count == 2)
        #expect(sessionA.prompts.first?.hasSuffix("turno um") == true)
        #expect(sessionA.prompts.last == "turno dois")
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

    @Test("Coach instructions forbid asking the user for data the app reads from Apple Health")
    func coachInstructionsForbidAskingForHealthData() {
        let instruction = CoachService.coachInstructions()

        #expect(instruction.contains("The app reads the user's Apple Health data for you"))
        #expect(instruction.contains("Never ask the user"))
        #expect(instruction.contains("never say you cannot access Apple Health"))
    }

    @Test("The first turn carries the user's Apple Health data; a follow-up in the same window does not")
    @MainActor
    func firstTurnIsGroundedInHealthData() async {
        let foundationModels = MockFoundationModelsService()
        let healthKit = MockHealthKitService()
        healthKit.dailySummariesToReturn = [
            DailyStepSummary(date: .now, steps: 4_321, distance: 3_000, floors: 0, calories: 120, goal: 10_000)
        ]
        let session = RetrySession(chunks: ["ok"])
        let service = CoachService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            sessionBuilder: { _, _ in session }
        )

        await service.send(message: "Pesquise no app health")
        await service.send(message: "e amanhã?")

        #expect(session.prompts.count == 2)
        let first = session.prompts.first ?? ""
        #expect(first.contains(Self.messageHeading))
        #expect(first.contains(Formatters.stepCountString(4_321)))
        #expect(first.hasSuffix("Pesquise no app health"))
        #expect(healthKit.lastFetchDailySummariesArgs?.days == CoachService.groundingDays)
        #expect(session.prompts.last == "e amanhã?")
        // The user sees what they typed, never the data block.
        #expect(service.messages.first?.content == "Pesquise no app health")
    }

    @Test("Grounding is refreshed when it is stale and whenever the session is rebuilt")
    @MainActor
    func groundingRefreshesWhenStaleOrRebuilt() async {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let session = RetrySession(chunks: ["ok"])
        let service = CoachService(
            foundationModelsService: MockFoundationModelsService(),
            healthKitService: MockHealthKitService(),
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            sessionBuilder: { _, _ in session },
            now: { clock }
        )

        await service.send(message: "um")
        clock = clock.addingTimeInterval(CoachService.groundingLifetime - 60)
        await service.send(message: "dois")
        clock = clock.addingTimeInterval(120)
        await service.send(message: "três")
        service.clearConversation()
        await service.send(message: "quatro")

        let grounded = session.prompts.map { $0.contains(Self.messageHeading) }
        #expect(grounded == [true, false, true, true])
    }

    @Test("A turn that asks about Apple Health carries fresh data even inside the grounding window",
          arguments: ["Pesquise no app health", "olha no Saúde", "check Apple Health", "HealthKit?"])
    @MainActor
    func healthQuestionReGrounds(question: String) async {
        let session = RetrySession(chunks: ["ok"])
        let service = CoachService(
            foundationModelsService: MockFoundationModelsService(),
            healthKitService: MockHealthKitService(),
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            sessionBuilder: { _, _ in session }
        )

        await service.send(message: "Crie um plano")
        await service.send(message: question)
        await service.send(message: "e amanhã?")

        let grounded = session.prompts.map { $0.contains(Self.messageHeading) }
        #expect(grounded == [true, true, false])
    }

    @Test("When Apple Health cannot be read, the turn says so in the user's language")
    @MainActor
    func groundingFailureIsLocalized() async {
        let healthKit = MockHealthKitService()
        healthKit.fetchDailySummariesHandler = { _ in throw CocoaError(.fileReadUnknown) }
        let session = RetrySession(chunks: ["ok"])
        let service = CoachService(
            foundationModelsService: MockFoundationModelsService(),
            healthKitService: healthKit,
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            sessionBuilder: { _, _ in session }
        )

        await service.send(message: "oi")

        let expected = L10n.localized(
            "Apple Health data could not be read right now.",
            comment: "AI Coach prompt line when reading Apple Health fails; the model may quote it to the user"
        )
        #expect(session.prompts.first?.contains(expected) == true)
        #expect(session.prompts.first?.hasSuffix("oi") == true)
        #expect(L10n.localized(
            "Apple Health data could not be read right now.",
            locale: Locale(identifier: "pt-BR"),
            comment: "AI Coach prompt line when reading Apple Health fails; the model may quote it to the user"
        ) == "Não foi possível ler os dados do app Saúde agora.")
    }

    @Test("A turn that fails does not count as grounded, so the next turn carries the data")
    @MainActor
    func failedTurnDoesNotConsumeGrounding() async {
        let session = FailOnceSession()
        let service = CoachService(
            foundationModelsService: MockFoundationModelsService(),
            healthKitService: MockHealthKitService(),
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            sessionBuilder: { _, _ in session }
        )

        await service.send(message: "um")
        await service.send(message: "dois")

        #expect(session.prompts.count == 2)
        #expect(session.prompts.allSatisfy { $0.contains(Self.messageHeading) })
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
private final class ContextWindowSession: CoachSessionProtocol {
    private let successfulCalls: Int
    private let maximumReplayBytes: Int
    private let response: String
    private(set) var prompts: [String] = []

    init(successfulCalls: Int, maximumReplayBytes: Int = .max, response: String) {
        self.successfulCalls = successfulCalls
        self.maximumReplayBytes = maximumReplayBytes
        self.response = response
    }

    static func replayBytes(in prompt: String) -> Int {
        guard prompt.hasPrefix("Earlier completed conversation"),
              let boundary = prompt.range(of: "\n\n") else { return 0 }
        return prompt[..<boundary.lowerBound].utf8.count
    }

    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, any Error> {
        prompts.append(prompt)
        let shouldFail = prompts.count > successfulCalls || Self.replayBytes(in: prompt) > maximumReplayBytes
        return AsyncThrowingStream { continuation in
            if shouldFail {
                continuation.finish(throwing: AIServiceError.tokenLimitExceeded)
            } else {
                continuation.yield(response)
                continuation.finish()
            }
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

@MainActor
private final class SucceedThenFailSession: CoachSessionProtocol {
    private var calls = 0

    func streamResponse(to _: String) -> AsyncThrowingStream<String, any Error> {
        calls += 1
        let shouldFail = calls > 1
        return AsyncThrowingStream { continuation in
            if shouldFail {
                continuation.finish(throwing: AIServiceError.generationFailed(underlying: "test failure"))
            } else {
                continuation.yield("Option one: a flat park. Option two: a steep hill.")
                continuation.finish()
            }
        }
    }
}

@MainActor
private final class FailOnceSession: CoachSessionProtocol {
    private(set) var prompts: [String] = []

    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, any Error> {
        prompts.append(prompt)
        let shouldFail = prompts.count == 1
        return AsyncThrowingStream { continuation in
            if shouldFail {
                continuation.finish(throwing: AIServiceError.generationFailed(underlying: "planted"))
            } else {
                continuation.yield("ok")
                continuation.finish()
            }
        }
    }
}
