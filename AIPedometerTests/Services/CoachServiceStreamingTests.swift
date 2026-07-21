import Dispatch
import Foundation
import Testing

@testable import AIPedometer

@MainActor
@Suite("CoachService Streaming Tests")
struct CoachServiceStreamingTests {
    @Test("Clearing conversation during stream prevents stale assistant append")
    func clearConversationInvalidatesInFlightResponse() async {
        let startGate = StreamStartGate(maximumBlocks: 1)
        let session = MockCoachSession(
            chunks: ["Parte 1", "Parte 2", "Parte 3"],
            startGate: startGate
        )
        let service = makeService(session: session)

        let sendTask = Task {
            await service.send(message: "teste")
        }

        await startGate.waitUntilBlocked(1)
        service.clearConversation()
        await startGate.releaseNext()
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
        let startGate = StreamStartGate(maximumBlocks: 1)
        let session = MockCoachSession(
            chunks: ["prefixo parcial"],
            startGate: startGate,
            terminalError: AIServiceError.generationFailed(underlying: "socket closed")
        )
        let service = makeService(session: session)

        let sendTask = Task {
            await service.send(message: "teste erro")
        }

        await startGate.waitUntilBlocked(1)
        service.clearConversation()
        await startGate.releaseNext()
        await sendTask.value

        #expect(service.messages.isEmpty)
        #expect({
            if case nil = service.lastError { return true }
            return false
        }())
    }

    @Test("Clearing conversation stops generating state immediately")
    func clearConversationStopsGeneratingStateImmediately() async {
        let startGate = StreamStartGate(maximumBlocks: 1)
        let session = MockCoachSession(
            chunks: ["resposta lenta"],
            startGate: startGate
        )
        let service = makeService(session: session)

        let sendTask = Task {
            await service.send(message: "mensagem lenta")
        }

        await startGate.waitUntilBlocked(1)
        #expect(service.isGenerating)

        service.clearConversation()
        await startGate.releaseNext()
        #expect(!service.isGenerating)
        #expect(service.currentStreamedContent.isEmpty)

        await sendTask.value
        #expect(service.messages.isEmpty)
    }

    @Test("Clearing conversation prevents stale streamed markdown render updates")
    func clearConversationPreventsStaleRenderedStreamUpdate() async {
        let startGate = StreamStartGate(maximumBlocks: 1)
        let session = MockCoachSession(
            chunks: ["**Par", "**Parcial**"],
            startGate: startGate
        )
        let service = makeService(session: session)

        let sendTask = Task {
            await service.send(message: "teste markdown")
        }

        await startGate.waitUntilBlocked(1)
        service.clearConversation()
        await startGate.releaseNext()
        await sendTask.value

        #expect(service.messages.isEmpty)
        #expect(String(service.currentStreamedRenderedContent.characters).isEmpty)
    }

    @Test("Service deallocates after clear to avoid streaming task retention cycles")
    func serviceDeallocatesAfterClear() async {
        let startGate = StreamStartGate(maximumBlocks: 1)
        let session = MockCoachSession(
            chunks: ["Parte 1", "Parte 2", "Parte 3"],
            startGate: startGate
        )

        var service: CoachService? = makeService(session: session)
        let weakService = WeakRef(service)

        let sendTask = Task { @MainActor [weak service] in
            await service?.send(message: "teste de release")
        }

        await startGate.waitUntilBlocked(1)
        service?.clearConversation()
        await startGate.releaseNext()
        await sendTask.value

        service = nil
        await Task.yield()
        await Task.yield()

        #expect(weakService.value == nil)
    }

    @Test("Can send a new message after clear without stale response leakage")
    func sendAfterClearDoesNotLeakStaleResponse() async {
        let startGate = StreamStartGate(maximumBlocks: 1)
        let session = MockCoachSession(
            chunks: ["resposta final"],
            startGate: startGate
        )
        let service = makeService(session: session)

        let firstTask = Task {
            await service.send(message: "primeira")
        }

        await startGate.waitUntilBlocked(1)
        service.clearConversation()
        await startGate.releaseNext()
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
        let startGate = StreamStartGate(maximumBlocks: 5)
        let session = MockCoachSession(
            chunks: ["parcial", "resposta final"],
            startGate: startGate
        )
        let service = makeService(session: session)

        for cycle in 1...5 {
            let sendTask = Task {
                await service.send(message: "mensagem \(cycle)")
            }

            await startGate.waitUntilBlocked(cycle)
            service.clearConversation()
            await startGate.releaseNext()
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
            renderProbe: renderProbe
        )
        let service = makeService(
            session: session,
            liveRenderer: { document in
                renderProbe.blockFirstRenderUntilNextRenderStarts()
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
        let startGate = StreamStartGate(maximumBlocks: 1)
        let session = MockCoachSession(
            chunks: ["parte 1", "parte 2"],
            startGate: startGate
        )
        let service = makeService(session: session)

        let sendTask = Task {
            await service.send(message: "teste")
        }

        await startGate.waitUntilBlocked(1)
        service.clearConversation()
        await startGate.releaseNext()
        await sendTask.value

        #expect(service.debugLastStreamRenderTelemetry == nil)
    }

    @Test("send rebuilds a nil session lazily when availability flips to available")
    func sendRebuildsSessionAfterAvailabilityFlip() async {
        let foundationModels = MockFoundationModelsService()
        foundationModels.availability = .unavailable(reason: .appleIntelligenceNotEnabled)

        let healthKit = MockHealthKitService()
        let goalService = GoalService(persistence: PersistenceController(inMemory: true))
        let session = MockCoachSession(chunks: ["recovered response"])

        var builderCallCount = 0
        let service = CoachService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: goalService,
            sessionBuilder: { _, _ in
                builderCallCount += 1
                return session
            }
        )
        #expect(builderCallCount == 0)

        // Simulates the OS availability flip while the app is running (2026-07-20 iOS 27
        // stale-banner bug): no foreground refresh runs, but the next send must self-heal
        // instead of answering with the "not available" fallback.
        foundationModels.availability = .available
        await service.send(message: "olá")

        #expect(builderCallCount == 1)
        #expect(session.prompts == ["olá"])
        #expect(service.messages.last?.content == "recovered response")
        #expect(service.lastError == nil)
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

private actor StreamStartGate {
    private var remainingBlocks: Int
    private var blockedCount = 0
    private var releasedCount = 0

    init(maximumBlocks: Int) {
        remainingBlocks = max(0, maximumBlocks)
    }

    func blockIfNeeded(timeout: Duration = .seconds(5)) async {
        guard remainingBlocks > 0 else { return }

        remainingBlocks -= 1
        blockedCount += 1
        let blockNumber = blockedCount
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while releasedCount < blockNumber {
            if Task.isCancelled {
                releasedCount = max(releasedCount, blockNumber)
                return
            }
            guard clock.now < deadline else {
                Issue.record("Timed out waiting to release stream block \(blockNumber)")
                releasedCount = max(releasedCount, blockNumber)
                return
            }
            await Task.yield()
        }
    }

    func waitUntilBlocked(_ target: Int, timeout: Duration = .seconds(5)) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while blockedCount < target {
            if Task.isCancelled { return }
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for stream block \(target)")
                releasedCount = max(releasedCount, target)
                return
            }
            await Task.yield()
        }
    }

    func releaseNext() {
        guard releasedCount < blockedCount else { return }
        releasedCount += 1
    }
}

private final class StreamRenderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let allowFirstRenderToFinish = DispatchSemaphore(value: 0)
    private var renderInvocationCount = 0
    private var firstRenderStarted = false
    private var isCancelled = false
    private var hasReleasedFirstRender = false

    /// Renders race the response loop's generation bump: a render that finishes before the
    /// loop schedules the newer generation commits as "current", which made the stale-after-render
    /// assertion flaky under load. The deterministic fix: the FIRST render blocks until a SECOND
    /// render invocation begins (which only happens after the loop scheduled the newer
    /// generation), so the first render's apply is structurally guaranteed to be stale.
    func blockFirstRenderUntilNextRenderStarts() {
        lock.lock()
        renderInvocationCount += 1
        let isFirstInvocation = renderInvocationCount == 1
        if !isFirstInvocation {
            let shouldSignal = !hasReleasedFirstRender
            hasReleasedFirstRender = true
            lock.unlock()
            if shouldSignal {
                allowFirstRenderToFinish.signal()
            }
            return
        }
        firstRenderStarted = true
        let cancelled = isCancelled
        lock.unlock()

        guard !cancelled else { return }
        guard allowFirstRenderToFinish.wait(timeout: .now() + .seconds(5)) == .success else {
            lock.lock()
            hasReleasedFirstRender = true
            lock.unlock()
            Issue.record("Timed out waiting for a subsequent render to release the first render")
            return
        }
    }

    func waitUntilFirstRenderStarts(timeout: Duration = .seconds(5)) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while true {
            let (didStart, wasCancelled) = lock.withLock {
                (firstRenderStarted, isCancelled)
            }

            if didStart || wasCancelled || Task.isCancelled { return }
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for the first stream render to start")
                cancel()
                return
            }
            await Task.yield()
        }
    }

    func releaseFirstRender() {
        lock.lock()
        let shouldSignal = !hasReleasedFirstRender
        hasReleasedFirstRender = true
        lock.unlock()

        if shouldSignal {
            allowFirstRenderToFinish.signal()
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let shouldSignal = !hasReleasedFirstRender
        hasReleasedFirstRender = true
        lock.unlock()

        if shouldSignal {
            allowFirstRenderToFinish.signal()
        }
    }
}

@MainActor
private final class CoordinatedCoachSession: CoachSessionProtocol {
    private let firstChunk: String
    private let secondChunk: String
    private let renderProbe: StreamRenderProbe

    init(
        firstChunk: String,
        secondChunk: String,
        renderProbe: StreamRenderProbe
    ) {
        self.firstChunk = firstChunk
        self.secondChunk = secondChunk
        self.renderProbe = renderProbe
    }

    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, any Error> {
        let firstChunk = self.firstChunk
        let secondChunk = self.secondChunk
        let renderProbe = self.renderProbe

        return AsyncThrowingStream { continuation in
            let task = Task {
                defer { renderProbe.releaseFirstRender() }
                continuation.yield(firstChunk)
                await renderProbe.waitUntilFirstRenderStarts()

                if Task.isCancelled {
                    continuation.finish(throwing: CancellationError())
                    return
                }

                continuation.yield(secondChunk)
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                renderProbe.cancel()
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
    private let startGate: StreamStartGate?
    private let terminalError: AIServiceError?
    private(set) var prompts: [String] = []

    init(
        chunks: [String],
        startGate: StreamStartGate? = nil,
        terminalError: AIServiceError? = nil
    ) {
        self.chunks = chunks
        self.startGate = startGate
        self.terminalError = terminalError
    }

    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, any Error> {
        prompts.append(prompt)

        let chunks = self.chunks
        let startGate = self.startGate
        let terminalError = self.terminalError

        return AsyncThrowingStream { continuation in
            let task = Task {
                await startGate?.blockIfNeeded()

                for chunk in chunks {
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
