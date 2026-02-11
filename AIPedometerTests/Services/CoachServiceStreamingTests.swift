import Foundation
import Testing

@testable import AIPedometer

@MainActor
@Suite("CoachService Streaming Tests")
struct CoachServiceStreamingTests {
    @Test("Clearing conversation during stream prevents stale assistant append")
    func clearConversationInvalidatesInFlightResponse() async {
        let session = MockCoachSession(
            chunks: ["Parte 1", "Parte 2", "Parte 3"],
            delayNanoseconds: 80_000_000
        )
        let service = makeService(session: session)

        let sendTask = Task {
            await service.send(message: "teste")
        }

        try? await Task.sleep(nanoseconds: 25_000_000)
        service.clearConversation()
        await sendTask.value

        #expect(service.messages.isEmpty)
        #expect({
            if case nil = service.lastError { return true }
            return false
        }())
        #expect(service.currentStreamedContent.isEmpty)
        #expect(!service.isGenerating)
    }

    @Test("Duplicate stream chunks are ignored and final content is preserved")
    func duplicateChunksDoNotBreakFinalMessage() async {
        let session = MockCoachSession(
            chunks: ["Oi", "Oi", "Oi **mundo**"]
        )
        let service = makeService(session: session)

        await service.send(message: "fala")

        #expect(service.messages.count == 2)
        let assistant = service.messages.last
        #expect(assistant?.role == .assistant)
        #expect(assistant?.content == "Oi **mundo**")
        #expect({
            if case nil = service.lastError { return true }
            return false
        }())
    }

    @Test("Very large final responses skip expensive markdown final render")
    func largeFinalResponseUsesPlainAttributedStringGuardrail() async {
        let large = String(repeating: "**x**", count: (CoachService.maxFinalMarkdownChars / 5) + 64)
        let session = MockCoachSession(chunks: [large])
        let service = makeService(session: session)

        await service.send(message: "gera texto grande")

        #expect(service.messages.count == 2)
        let assistant = service.messages.last
        #expect(assistant?.role == .assistant)
        #expect(assistant?.content == large)

        let rendered = assistant?.renderedContent.map { String($0.characters) }
        #expect(rendered == large)
    }

    @Test("Terminal stream error appends localized assistant fallback")
    func terminalStreamErrorAppendsFallbackMessage() async {
        let session = MockCoachSession(
            chunks: ["prefixo parcial"],
            terminalError: AIServiceError.guardrailViolation
        )
        let service = makeService(session: session)

        await service.send(message: "mensagem")

        #expect(service.messages.count == 2)
        let assistant = service.messages.last
        #expect(assistant?.role == .assistant)
        #expect(assistant?.content == AIServiceError.guardrailViolation.localizedDescription)
        #expect({
            if case nil = assistant?.terminalError { return true }
            return false
        }())
        #expect({
            if case .guardrailViolation = service.lastError { return true }
            return false
        }())
    }

    @Test("Terminal recoverable error preserves partial assistant response")
    func terminalRecoverableErrorPreservesPartialAssistantResponse() async {
        let session = MockCoachSession(
            chunks: ["Resposta **parcial**"],
            terminalError: AIServiceError.generationFailed(underlying: "socket closed")
        )
        let service = makeService(session: session)

        await service.send(message: "mensagem")

        #expect(service.messages.count == 2)
        let assistant = service.messages.last
        #expect(assistant?.role == .assistant)
        #expect(assistant?.content == "Resposta **parcial**")
        #expect({
            if case .generationFailed = assistant?.terminalError { return true }
            return false
        }())
        #expect({
            if case .generationFailed = service.lastError { return true }
            return false
        }())
    }

    @Test("Token-limit terminal error preserves partial assistant response")
    func tokenLimitTerminalErrorPreservesPartialAssistantResponse() async {
        let session = MockCoachSession(
            chunks: ["Resposta parcial até limite"],
            terminalError: AIServiceError.tokenLimitExceeded
        )
        let service = makeService(session: session)

        await service.send(message: "mensagem longa")

        #expect(service.messages.count == 2)
        let assistant = service.messages.last
        #expect(assistant?.role == .assistant)
        #expect(assistant?.content == "Resposta parcial até limite")
        #expect({
            if case .tokenLimitExceeded = assistant?.terminalError { return true }
            return false
        }())
        #expect({
            if case .tokenLimitExceeded = service.lastError { return true }
            return false
        }())
    }

    @Test("Empty stream appends invalid-response assistant fallback")
    func emptyStreamAppendsInvalidResponseFallback() async {
        let session = MockCoachSession(chunks: [])
        let service = makeService(session: session)

        await service.send(message: "mensagem")

        #expect(service.messages.count == 2)
        let assistant = service.messages.last
        #expect(assistant?.role == .assistant)
        #expect(assistant?.content == AIServiceError.invalidResponse.localizedDescription)
        #expect({
            if case nil = assistant?.terminalError { return true }
            return false
        }())
        #expect({
            if case .invalidResponse = service.lastError { return true }
            return false
        }())
    }

    @Test("Clearing conversation during stream suppresses stale terminal error")
    func clearConversationSuppressesStaleTerminalError() async {
        let session = MockCoachSession(
            chunks: ["prefixo parcial"],
            delayNanoseconds: 90_000_000,
            terminalError: AIServiceError.generationFailed(underlying: "socket closed")
        )
        let service = makeService(session: session)

        let sendTask = Task {
            await service.send(message: "teste erro")
        }

        try? await Task.sleep(nanoseconds: 25_000_000)
        service.clearConversation()
        await sendTask.value

        #expect(service.messages.isEmpty)
        #expect({
            if case nil = service.lastError { return true }
            return false
        }())
    }

    @Test("Clearing conversation stops generating state immediately")
    func clearConversationStopsGeneratingStateImmediately() async {
        let session = MockCoachSession(
            chunks: ["resposta lenta"],
            delayNanoseconds: 150_000_000
        )
        let service = makeService(session: session)

        let sendTask = Task {
            await service.send(message: "mensagem lenta")
        }

        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(service.isGenerating)

        service.clearConversation()
        #expect(!service.isGenerating)
        #expect(service.currentStreamedContent.isEmpty)

        await sendTask.value
        #expect(service.messages.isEmpty)
    }

    @Test("Clearing conversation prevents stale streamed markdown render updates")
    func clearConversationPreventsStaleRenderedStreamUpdate() async {
        let session = MockCoachSession(
            chunks: ["**Par", "**Parcial**"],
            delayNanoseconds: 80_000_000
        )
        let service = makeService(session: session)

        let sendTask = Task {
            await service.send(message: "teste markdown")
        }

        try? await Task.sleep(nanoseconds: 25_000_000)
        service.clearConversation()
        await sendTask.value

        #expect(service.messages.isEmpty)
        #expect(String(service.currentStreamedRenderedContent.characters).isEmpty)
    }

    @Test("Service deallocates after clear to avoid streaming task retention cycles")
    func serviceDeallocatesAfterClear() async {
        let session = MockCoachSession(
            chunks: ["Parte 1", "Parte 2", "Parte 3"],
            delayNanoseconds: 70_000_000
        )

        var service: CoachService? = makeService(session: session)
        let weakService = WeakRef(service)

        let sendTask = Task { @MainActor [weak service] in
            await service?.send(message: "teste de release")
        }

        try? await Task.sleep(nanoseconds: 20_000_000)
        service?.clearConversation()
        await sendTask.value

        service = nil
        await Task.yield()
        await Task.yield()

        #expect(weakService.value == nil)
    }

    @Test("Can send a new message after clear without stale response leakage")
    func sendAfterClearDoesNotLeakStaleResponse() async {
        let session = MockCoachSession(
            chunks: ["resposta final"],
            delayNanoseconds: 120_000_000
        )
        let service = makeService(session: session)

        let firstTask = Task {
            await service.send(message: "primeira")
        }

        try? await Task.sleep(nanoseconds: 20_000_000)
        service.clearConversation()
        #expect(!service.isGenerating)

        await service.send(message: "segunda")
        await firstTask.value

        #expect(service.messages.count == 2)
        #expect(service.messages.first?.role == .user)
        #expect(service.messages.first?.content == "segunda")
        #expect(service.messages.last?.role == .assistant)
        #expect(service.messages.last?.content == "resposta final")
    }

    @Test("Repeated clear and resend cycles stay deterministic and leak-free")
    func repeatedClearAndResendCyclesStayDeterministic() async {
        let session = MockCoachSession(
            chunks: ["parcial", "resposta final"],
            delayNanoseconds: 45_000_000
        )
        let service = makeService(session: session)

        for cycle in 1...5 {
            let sendTask = Task {
                await service.send(message: "mensagem \(cycle)")
            }

            try? await Task.sleep(nanoseconds: 12_000_000)
            service.clearConversation()
            await sendTask.value

            #expect(service.messages.isEmpty)
            #expect(service.currentStreamedContent.isEmpty)
            #expect(String(service.currentStreamedRenderedContent.characters).isEmpty)
            #expect(!service.isGenerating)
        }

        await service.send(message: "final")
        #expect(service.messages.count == 2)
        #expect(service.messages.first?.content == "final")
        #expect(service.messages.last?.content == "resposta final")
    }

    @Test("Burst snapshots are coalesced by stream render backpressure")
    func burstSnapshotsAreCoalesced() async throws {
        var chunks: [String] = []
        var current = ""
        for item in 1...120 {
            current += "- item \(item)\n"
            chunks.append(current)
        }

        let session = MockCoachSession(chunks: chunks)
        let service = makeService(session: session)

        await service.send(message: "burst")

        #expect(service.messages.count == 2)
        #expect(service.messages.last?.content == chunks.last)

        let telemetry = try #require(service.debugLastStreamRenderTelemetry)
        #expect(telemetry.scheduledUpdates >= chunks.count - 1)
        #expect(telemetry.committedUpdates < telemetry.scheduledUpdates)
        #expect(telemetry.droppedByBackpressure >= 1)
        #expect(telemetry.terminatedInputYields == 0)
        #expect(telemetry.uncommittedUpdates >= 1)
        #expect(telemetry.droppedByBackpressure <= telemetry.uncommittedUpdates)
        #expect(
            telemetry.staleDiscardedUpdates ==
            telemetry.staleDiscardedBeforeRender + telemetry.staleDiscardedAfterRender
        )
        #expect(
            telemetry.scheduledUpdates ==
            telemetry.committedUpdates + telemetry.staleDiscardedUpdates + telemetry.uncommittedUpdates
        )
        #expect(telemetry.responseLength == (chunks.last?.count ?? 0))
    }

    @Test("Slow live renderer records stale-after-render telemetry")
    func slowRendererRecordsAfterRenderStale() async throws {
        let renderProbe = StreamRenderProbe()
        let session = CoordinatedCoachSession(
            firstChunk: "**primeira**",
            secondChunk: "**segunda**",
            renderProbe: renderProbe,
            finishDelayNanoseconds: 180_000_000
        )
        let service = makeService(
            session: session,
            liveRenderer: { document in
                Task {
                    await renderProbe.markFirstRenderStarted()
                }
                Thread.sleep(forTimeInterval: 0.12)
                return AIChatMarkdown.renderAttributedString(from: document)
            }
        )

        await service.send(message: "slow-render")

        #expect(service.messages.count == 2)
        #expect(service.messages.last?.content == "**segunda**")

        let telemetry = try #require(service.debugLastStreamRenderTelemetry)
        #expect(telemetry.staleDiscardedAfterRender >= 1)
        #expect(
            telemetry.staleDiscardedUpdates ==
            telemetry.staleDiscardedBeforeRender + telemetry.staleDiscardedAfterRender
        )
    }

    @Test("Clear during stream does not publish stale telemetry snapshot")
    func clearDuringStreamDoesNotPublishStaleTelemetry() async {
        let session = MockCoachSession(
            chunks: ["parte 1", "parte 2"],
            delayNanoseconds: 70_000_000
        )
        let service = makeService(session: session)

        let sendTask = Task {
            await service.send(message: "teste")
        }

        try? await Task.sleep(nanoseconds: 20_000_000)
        service.clearConversation()
        await sendTask.value

        #expect(service.debugLastStreamRenderTelemetry == nil)
    }

    private func makeService(
        session: any CoachSessionProtocol,
        liveRenderer: CoachService.LiveMarkdownRenderer? = nil
    ) -> CoachService {
        let foundationModels = MockFoundationModelsService()
        foundationModels.availability = .available

        let healthKit = MockHealthKitService()
        let goalService = GoalService(persistence: PersistenceController(inMemory: true))

        return CoachService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: goalService,
            sessionBuilder: { _, _ in session },
            liveMarkdownRenderer: liveRenderer
        )
    }
}

private actor StreamRenderProbe {
    private var firstRenderStarted = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markFirstRenderStarted() {
        guard !firstRenderStarted else { return }
        firstRenderStarted = true
        let currentWaiters = waiters
        waiters.removeAll()
        for waiter in currentWaiters {
            waiter.resume()
        }
    }

    func waitUntilFirstRenderStarts() async {
        if firstRenderStarted {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

@MainActor
private final class CoordinatedCoachSession: CoachSessionProtocol {
    private let firstChunk: String
    private let secondChunk: String
    private let renderProbe: StreamRenderProbe
    private let finishDelayNanoseconds: UInt64

    init(
        firstChunk: String,
        secondChunk: String,
        renderProbe: StreamRenderProbe,
        finishDelayNanoseconds: UInt64
    ) {
        self.firstChunk = firstChunk
        self.secondChunk = secondChunk
        self.renderProbe = renderProbe
        self.finishDelayNanoseconds = finishDelayNanoseconds
    }

    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, any Error> {
        let firstChunk = self.firstChunk
        let secondChunk = self.secondChunk
        let renderProbe = self.renderProbe
        let finishDelayNanoseconds = self.finishDelayNanoseconds

        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(firstChunk)
                await renderProbe.waitUntilFirstRenderStarts()

                if Task.isCancelled {
                    continuation.finish(throwing: CancellationError())
                    return
                }

                continuation.yield(secondChunk)

                if finishDelayNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: finishDelayNanoseconds)
                }

                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

private final class WeakRef<T: AnyObject> {
    weak var value: T?

    init(_ value: T?) {
        self.value = value
    }
}

@Suite("AI Coach Error Presentation Policy Tests")
struct AICoachErrorPresentationPolicyTests {
    @Test("Shows global banner when there is no assistant message yet")
    func showsBannerWhenNoAssistantMessage() {
        let messages = [
            ChatMessage(role: .user, content: "u")
        ]

        let shouldShow = AICoachErrorPresentationPolicy.shouldShowGlobalErrorBanner(
            lastError: .generationFailed(underlying: "network"),
            messages: messages
        )
        #expect(shouldShow == true)
    }

    @Test("Hides global banner when last assistant has same terminal error kind")
    func hidesBannerWhenInlineErrorMatches() {
        let messages = [
            ChatMessage(role: .user, content: "u"),
            ChatMessage(
                role: .assistant,
                content: "partial",
                terminalError: .tokenLimitExceeded
            )
        ]

        let shouldShow = AICoachErrorPresentationPolicy.shouldShowGlobalErrorBanner(
            lastError: .tokenLimitExceeded,
            messages: messages
        )
        #expect(shouldShow == false)
    }

    @Test("generationFailed comparison ignores underlying reason")
    func generationFailedComparisonIgnoresUnderlyingReason() {
        #expect(
            AICoachErrorPresentationPolicy.isSameErrorKind(
                .generationFailed(underlying: "socket"),
                .generationFailed(underlying: "timeout")
            )
        )
    }

    @Test("Shows global banner when last assistant has no inline terminal error")
    func showsBannerWhenNoInlineError() {
        let messages = [
            ChatMessage(role: .user, content: "u"),
            ChatMessage(role: .assistant, content: "fallback")
        ]

        let shouldShow = AICoachErrorPresentationPolicy.shouldShowGlobalErrorBanner(
            lastError: .guardrailViolation,
            messages: messages
        )
        #expect(shouldShow == true)
    }

    @Test("Shows global banner when inline terminal error differs from last error")
    func showsBannerWhenInlineErrorDiffers() {
        let messages = [
            ChatMessage(role: .assistant, content: "partial", terminalError: .generationFailed(underlying: "socket"))
        ]

        let shouldShow = AICoachErrorPresentationPolicy.shouldShowGlobalErrorBanner(
            lastError: .guardrailViolation,
            messages: messages
        )
        #expect(shouldShow == true)
    }

    @Test("Model-unavailable comparison uses reason equality")
    func modelUnavailableComparisonUsesReason() {
        #expect(
            AICoachErrorPresentationPolicy.isSameErrorKind(
                .modelUnavailable(.modelNotReady),
                .modelUnavailable(.modelNotReady)
            )
        )
        #expect(
            !AICoachErrorPresentationPolicy.isSameErrorKind(
                .modelUnavailable(.modelNotReady),
                .modelUnavailable(.appleIntelligenceNotEnabled)
            )
        )
    }
}

@MainActor
private final class MockCoachSession: CoachSessionProtocol {
    private let chunks: [String]
    private let delayNanoseconds: UInt64
    private let terminalError: AIServiceError?
    private(set) var prompts: [String] = []

    init(
        chunks: [String],
        delayNanoseconds: UInt64 = 0,
        terminalError: AIServiceError? = nil
    ) {
        self.chunks = chunks
        self.delayNanoseconds = delayNanoseconds
        self.terminalError = terminalError
    }

    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, any Error> {
        prompts.append(prompt)

        let chunks = self.chunks
        let delayNanoseconds = self.delayNanoseconds
        let terminalError = self.terminalError

        return AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in chunks {
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }

                    if delayNanoseconds > 0 {
                        try? await Task.sleep(nanoseconds: delayNanoseconds)
                    }

                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }

                    continuation.yield(chunk)
                }

                if let terminalError {
                    continuation.finish(throwing: terminalError)
                } else {
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
