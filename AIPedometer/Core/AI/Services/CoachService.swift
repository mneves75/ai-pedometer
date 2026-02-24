import Foundation
import FoundationModels
import Observation
import SwiftFastMarkdown

@MainActor
protocol CoachSessionProtocol: AnyObject {
    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, any Error>
}

@MainActor
private final class LanguageModelCoachSession: CoachSessionProtocol {
    private let session: LanguageModelSession

    init(session: LanguageModelSession) {
        self.session = session
    }

    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, any Error> {
        // Foundation Models stream emits full-content snapshots; keeping only the newest
        // snapshot avoids backlog growth if UI work briefly lags behind generation.
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor [session] in
                do {
                    let stream = session.streamResponse(to: prompt)
                    for try await partialResponse in stream {
                        if Task.isCancelled {
                            continuation.finish(throwing: CancellationError())
                            return
                        }
                        continuation.yield(partialResponse.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    let renderedContent: AttributedString?
    let terminalError: AIServiceError?
    
    enum Role: String, Sendable {
        case user
        case assistant
    }
    
    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        renderedContent: AttributedString? = nil,
        terminalError: AIServiceError? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.renderedContent = renderedContent
        self.terminalError = terminalError
    }
}

@MainActor
@Observable
final class CoachService {
    typealias SessionBuilder = @MainActor (_ tools: [any Tool], _ instructions: String) -> (any CoachSessionProtocol)?
    typealias LiveMarkdownRenderer = @Sendable (_ document: MarkdownDocument) -> AttributedString

    struct StreamRenderTelemetry: Sendable {
        let scheduledUpdates: Int
        let committedUpdates: Int
        let staleDiscardedUpdates: Int
        let staleDiscardedBeforeRender: Int
        let staleDiscardedAfterRender: Int
        let droppedByBackpressure: Int
        let terminatedInputYields: Int
        let uncommittedUpdates: Int
        let responseLength: Int
    }

    private struct StreamRenderRequest: Sendable {
        let generation: UInt64
        let document: MarkdownDocument
    }

    private let foundationModelsService: any FoundationModelsServiceProtocol
    private let healthKitService: any HealthKitServiceProtocol
    private let goalService: GoalService
    private let sessionBuilder: SessionBuilder
    private let liveMarkdownRenderer: LiveMarkdownRenderer
    
    @ObservationIgnored private var session: (any CoachSessionProtocol)?
    @ObservationIgnored private var streamAccumulator = AIStreamMarkdownAccumulator()
    @ObservationIgnored private var streamRenderInputContinuation: AsyncStream<StreamRenderRequest>.Continuation?
    @ObservationIgnored private var streamRenderWorkerTask: Task<Void, Never>?
    @ObservationIgnored private var finalRenderTask: Task<AttributedString, Never>?
    @ObservationIgnored private var activeResponseTask: Task<Void, Never>?
    @ObservationIgnored private var activeResponseTaskGeneration: UInt64 = 0
    @ObservationIgnored private var streamRenderGeneration: UInt64 = 0
    @ObservationIgnored private var responseGeneration: UInt64 = 0
    @ObservationIgnored private var streamRenderScheduledUpdates = 0
    @ObservationIgnored private var streamRenderCommittedUpdates = 0
    @ObservationIgnored private var streamRenderStaleDiscardedBeforeRender = 0
    @ObservationIgnored private var streamRenderStaleDiscardedAfterRender = 0
    @ObservationIgnored private var streamRenderDroppedByBackpressure = 0
    @ObservationIgnored private var streamRenderTerminatedInputYields = 0
    
    private(set) var messages: [ChatMessage] = []
    private(set) var isGenerating = false
    private(set) var currentStreamedContent = ""
    private(set) var currentStreamedRenderedContent = AttributedString()
    private(set) var lastError: AIServiceError?
    @ObservationIgnored private(set) var debugLastStreamRenderTelemetry: StreamRenderTelemetry?

    /// Guardrail: live markdown rendering is intentionally capped.
    /// We always render the final message, but we avoid repeated heavy renders for very large streams.
    static let maxLiveMarkdownChars = 20_000
    /// Guardrail: for very large completions, skip final markdown parse/render to keep UI responsive.
    static let maxFinalMarkdownChars = 80_000
    /// Coalesce bursty token updates into fewer markdown renders.
    static let streamRenderDebounce = Duration.milliseconds(30)
    
    static var suggestedQuestions: [String] {
        [
            L10n.localized("How did I do this week?", comment: "Suggested AI Coach question about weekly performance"),
            L10n.localized("What's my best day for walking?", comment: "Suggested AI Coach question about best walking day"),
            L10n.localized("Should I increase my goal?", comment: "Suggested AI Coach question about increasing goal"),
            L10n.localized("Create a plan to reach 10,000 steps", comment: "Suggested AI Coach question about creating a plan"),
            L10n.localized("Why am I not hitting my goals?", comment: "Suggested AI Coach question about missing goals")
        ]
    }

    var suggestedQuestions: [String] {
        Self.suggestedQuestions
    }
    
    init(
        foundationModelsService: any FoundationModelsServiceProtocol,
        healthKitService: any HealthKitServiceProtocol,
        goalService: GoalService,
        sessionBuilder: SessionBuilder? = nil,
        liveMarkdownRenderer: LiveMarkdownRenderer? = nil
    ) {
        self.foundationModelsService = foundationModelsService
        self.healthKitService = healthKitService
        self.goalService = goalService
        self.sessionBuilder = sessionBuilder ?? { tools, instructions in
            let session = LanguageModelSession(
                tools: tools,
                instructions: instructions
            )
            return LanguageModelCoachSession(session: session)
        }
        self.liveMarkdownRenderer = liveMarkdownRenderer ?? { document in
            AIChatMarkdown.renderAttributedString(from: document)
        }
        
        configureSession()
    }

    func send(message: String) async {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isGenerating else { return }

        activeResponseTaskGeneration &+= 1
        let taskGeneration = activeResponseTaskGeneration
        let responseTask = Task { @MainActor [self] in
            await runResponse(message: message, taskGeneration: taskGeneration)
        }
        activeResponseTask = responseTask
        await responseTask.value

        if taskGeneration == activeResponseTaskGeneration {
            activeResponseTask = nil
        }
    }

    private func runResponse(message: String, taskGeneration: UInt64) async {
        guard taskGeneration == activeResponseTaskGeneration else { return }
        responseGeneration &+= 1
        let generation = responseGeneration
        var fullResponse = ""
        
        let userMessage = ChatMessage(role: .user, content: message)
        messages.append(userMessage)
        
        isGenerating = true
        currentStreamedContent = ""
        currentStreamedRenderedContent = AttributedString()
        streamAccumulator.reset()
        cancelPendingResponseWork()
        startStreamRenderPipeline()
        streamRenderScheduledUpdates = 0
        streamRenderCommittedUpdates = 0
        streamRenderStaleDiscardedBeforeRender = 0
        streamRenderStaleDiscardedAfterRender = 0
        streamRenderDroppedByBackpressure = 0
        streamRenderTerminatedInputYields = 0
        debugLastStreamRenderTelemetry = nil
        lastError = nil
        
        defer {
            cancelPendingResponseWork()
            if generation == responseGeneration {
                let streamRenderTelemetry = makeStreamRenderTelemetry(responseLength: fullResponse.count)
                debugLastStreamRenderTelemetry = streamRenderTelemetry
                logStreamRenderTelemetry(streamRenderTelemetry)
                isGenerating = false
                currentStreamedContent = ""
                currentStreamedRenderedContent = AttributedString()
            }
        }
        
        guard let session else {
            lastError = .sessionNotConfigured
            messages.append(ChatMessage(
                role: .assistant,
                content: String(
                    localized: "I'm sorry, I'm not available right now. Please try again later.",
                    comment: "AI Coach fallback response when the model session is unavailable"
                )
            ))
            return
        }

        var exceededLiveMarkdownLimit = false
        
        do {
            let stream = session.streamResponse(to: message)
            
            for try await newContent in stream {
                guard generation == responseGeneration else { return }
                guard newContent != fullResponse else { continue }
                fullResponse = newContent
                currentStreamedContent = newContent

                if exceededLiveMarkdownLimit {
                    continue
                }

                guard newContent.count <= Self.maxLiveMarkdownChars else {
                    // Stop burning CPU during stream; show plain text.
                    // We'll parse+render once at the end to keep final output correct.
                    exceededLiveMarkdownLimit = true
                    streamAccumulator.reset()
                    cancelPendingStreamRendering()
                    currentStreamedRenderedContent = AttributedString()
                    continue
                }

                if let document = streamAccumulator.ingest(fullContent: newContent) {
                    scheduleStreamRender(document: document)
                }
            }

            // Render final message once (off-main) to avoid reparsing in the list.
            let finalSignpost = Signposts.ai.begin("CoachFinalMarkdownRender")
            defer { Signposts.ai.end("CoachFinalMarkdownRender", finalSignpost) }
            guard generation == responseGeneration else { return }
            guard !fullResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                let mappedError = AIServiceError.invalidResponse
                lastError = mappedError
                messages.append(ChatMessage(
                    role: .assistant,
                    content: errorMessage(for: mappedError)
                ))
                Loggers.ai.error("ai.coach_response_empty", metadata: [
                    "error": mappedError.logDescription
                ])
                return
            }

            let finalAttributed = await renderFinalAttributedResponse(
                fullResponse: fullResponse,
                exceededLiveMarkdownLimit: exceededLiveMarkdownLimit
            )
            guard generation == responseGeneration else { return }

            let assistantMessage = ChatMessage(
                role: .assistant,
                content: fullResponse,
                renderedContent: finalAttributed
            )
            messages.append(assistantMessage)
            
            Loggers.ai.info("ai.coach_response_completed", metadata: [
                "message_length": "\(fullResponse.count)"
            ])
        } catch {
            if error is CancellationError || generation != responseGeneration {
                return
            }

            let mappedError = mapError(error)
            lastError = mappedError

            let hasPartialResponse = !fullResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasPartialResponse && shouldPreservePartialResponse(for: mappedError) {
                let finalAttributed = await renderFinalAttributedResponse(
                    fullResponse: fullResponse,
                    exceededLiveMarkdownLimit: exceededLiveMarkdownLimit
                )
                guard generation == responseGeneration else { return }

                messages.append(ChatMessage(
                    role: .assistant,
                    content: fullResponse,
                    renderedContent: finalAttributed,
                    terminalError: mappedError
                ))

                Loggers.ai.error("ai.coach_response_partial", metadata: [
                    "error": mappedError.logDescription,
                    "message_length": "\(fullResponse.count)"
                ])
                return
            }
            
            messages.append(ChatMessage(
                role: .assistant,
                content: errorMessage(for: mappedError)
            ))
            
            Loggers.ai.error("ai.coach_response_failed", metadata: [
                "error": mappedError.logDescription
            ])
        }
    }
    
    func clearConversation() {
        responseGeneration &+= 1
        cancelActiveResponseTask()
        messages.removeAll()
        configureSession()
        streamAccumulator.reset()
        lastError = nil
        isGenerating = false
        currentStreamedContent = ""
        currentStreamedRenderedContent = AttributedString()
        Loggers.ai.info("ai.coach_conversation_cleared")
    }

    func refreshSession() {
        configureSession()
    }
    
    func retryLastMessage() async {
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else { return }
        
        if let lastAssistantIndex = messages.lastIndex(where: { $0.role == .assistant }),
           lastAssistantIndex == messages.count - 1 {
            messages.removeLast()
        }
        
        if messages.last?.role == .user {
            messages.removeLast()
        }
        
        await send(message: lastUserMessage.content)
    }
    
    private func configureSession() {
        guard foundationModelsService.availability.isAvailable else {
            session = nil
            return
        }
        
        let tools: [any Tool] = [
            HealthKitDataTool(healthKitService: healthKitService, goalService: goalService),
            GoalDataTool(goalService: goalService),
            StreakDataTool()
        ]

        session = sessionBuilder(tools, Self.coachInstructions())
    }

    private func scheduleStreamRender(document: MarkdownDocument) {
        guard let continuation = streamRenderInputContinuation else { return }

        streamRenderGeneration &+= 1
        let generation = streamRenderGeneration
        let request = StreamRenderRequest(generation: generation, document: document)
        let yieldResult = continuation.yield(request)
        switch yieldResult {
        case .enqueued:
            streamRenderScheduledUpdates += 1
        case .dropped:
            streamRenderScheduledUpdates += 1
            streamRenderDroppedByBackpressure += 1
        case .terminated:
            streamRenderTerminatedInputYields += 1
        @unknown default:
            break
        }
    }

    private func startStreamRenderPipeline() {
        cancelPendingStreamRendering()

        let inputStream = AsyncStream<StreamRenderRequest>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            streamRenderInputContinuation = continuation
        }
        let liveMarkdownRenderer = self.liveMarkdownRenderer

        streamRenderWorkerTask = Task.detached(priority: .userInitiated) { [weak self] in
            for await request in inputStream {
                if Task.isCancelled { return }
                try? await Task.sleep(for: Self.streamRenderDebounce)
                if Task.isCancelled { return }
                guard await self?.shouldRenderStreamRequest(generation: request.generation) == true else {
                    continue
                }

                let liveSignpost = Signposts.ai.begin("CoachLiveMarkdownRender")
                let attributed = liveMarkdownRenderer(request.document)
                Signposts.ai.end("CoachLiveMarkdownRender", liveSignpost)

                await self?.applyStreamRenderResult(generation: request.generation, attributed: attributed)
            }
        }
    }

    private func cancelPendingStreamRendering() {
        streamRenderInputContinuation?.finish()
        streamRenderInputContinuation = nil
        streamRenderWorkerTask?.cancel()
        streamRenderWorkerTask = nil
        streamRenderGeneration &+= 1
    }

    private func cancelPendingResponseWork() {
        cancelPendingStreamRendering()
        finalRenderTask?.cancel()
        finalRenderTask = nil
    }

    private func cancelActiveResponseTask() {
        activeResponseTaskGeneration &+= 1
        activeResponseTask?.cancel()
        activeResponseTask = nil
        cancelPendingResponseWork()
    }

    private func renderFinalAttributedResponse(
        fullResponse: String,
        exceededLiveMarkdownLimit: Bool
    ) async -> AttributedString {
        let incrementalFinalDocument: MarkdownDocument? = exceededLiveMarkdownLimit ? nil : streamAccumulator.finalize()
        let maxFinalMarkdownChars = Self.maxFinalMarkdownChars

        let renderTask = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return AttributedString() }

            if fullResponse.count > maxFinalMarkdownChars {
                return AttributedString(fullResponse)
            }

            if exceededLiveMarkdownLimit {
                do {
                    let document = try AIChatMarkdown.parseDocument(from: fullResponse)
                    return AIChatMarkdown.renderAttributedString(from: document)
                } catch {
                    return AttributedString(fullResponse)
                }
            }

            if let incrementalFinalDocument {
                return AIChatMarkdown.renderAttributedString(from: incrementalFinalDocument)
            }

            return AttributedString(fullResponse)
        }

        finalRenderTask?.cancel()
        finalRenderTask = renderTask
        let finalAttributed = await renderTask.value
        finalRenderTask = nil
        return finalAttributed
    }

    private func shouldRenderStreamRequest(generation: UInt64) -> Bool {
        guard generation == streamRenderGeneration else {
            streamRenderStaleDiscardedBeforeRender += 1
            return false
        }
        return true
    }

    private func applyStreamRenderResult(generation: UInt64, attributed: AttributedString) {
        guard generation == streamRenderGeneration else {
            streamRenderStaleDiscardedAfterRender += 1
            return
        }
        streamRenderCommittedUpdates += 1
        currentStreamedRenderedContent = attributed
    }

    private func makeStreamRenderTelemetry(responseLength: Int) -> StreamRenderTelemetry {
        let staleDiscardedUpdates =
            streamRenderStaleDiscardedBeforeRender + streamRenderStaleDiscardedAfterRender
        let uncommittedUpdates = max(
            0,
            streamRenderScheduledUpdates - streamRenderCommittedUpdates - staleDiscardedUpdates
        )

        return StreamRenderTelemetry(
            scheduledUpdates: streamRenderScheduledUpdates,
            committedUpdates: streamRenderCommittedUpdates,
            staleDiscardedUpdates: staleDiscardedUpdates,
            staleDiscardedBeforeRender: streamRenderStaleDiscardedBeforeRender,
            staleDiscardedAfterRender: streamRenderStaleDiscardedAfterRender,
            droppedByBackpressure: streamRenderDroppedByBackpressure,
            terminatedInputYields: streamRenderTerminatedInputYields,
            uncommittedUpdates: uncommittedUpdates,
            responseLength: responseLength
        )
    }

    private func logStreamRenderTelemetry(_ telemetry: StreamRenderTelemetry) {
        let metadata = [
            "scheduled_updates": "\(telemetry.scheduledUpdates)",
            "committed_updates": "\(telemetry.committedUpdates)",
            "stale_discarded_updates": "\(telemetry.staleDiscardedUpdates)",
            "stale_discarded_before_render": "\(telemetry.staleDiscardedBeforeRender)",
            "stale_discarded_after_render": "\(telemetry.staleDiscardedAfterRender)",
            "dropped_by_backpressure": "\(telemetry.droppedByBackpressure)",
            "terminated_input_yields": "\(telemetry.terminatedInputYields)",
            "uncommitted_updates": "\(telemetry.uncommittedUpdates)",
            "response_length": "\(telemetry.responseLength)"
        ]

        if telemetry.staleDiscardedAfterRender > 0 {
            Loggers.ai.warning("ai.coach_stream_render_backpressure", metadata: metadata)
        } else if telemetry.staleDiscardedBeforeRender > 0 || telemetry.uncommittedUpdates > 0 {
            Loggers.ai.info("ai.coach_stream_render_coalesced", metadata: metadata)
        } else {
            Loggers.ai.info("ai.coach_stream_render_stats", metadata: metadata)
        }
    }

    private func shouldPreservePartialResponse(for error: AIServiceError) -> Bool {
        switch error {
        case .generationFailed, .tokenLimitExceeded:
            return true
        case .sessionNotConfigured, .modelUnavailable, .guardrailViolation, .invalidResponse:
            return false
        }
    }
    
    private func mapError(_ error: any Error) -> AIServiceError {
        if let aiError = error as? AIServiceError {
            return aiError
        }
        
        if let sessionError = error as? LanguageModelSession.GenerationError {
            switch sessionError {
            case .exceededContextWindowSize:
                return .tokenLimitExceeded
            case .guardrailViolation, .refusal:
                return .guardrailViolation
            case .assetsUnavailable:
                return .modelUnavailable(.modelNotReady)
            default:
                return .generationFailed(underlying: error.localizedDescription)
            }
        }
        
        return .generationFailed(underlying: error.localizedDescription)
    }
    
    private func errorMessage(for error: AIServiceError) -> String {
        error.localizedDescription
    }
}

extension CoachService {
    nonisolated static func coachInstructions(
        languageInstruction: String = AppLanguage.promptInstruction()
    ) -> String {
        """
        You are a supportive, encouraging fitness coach helping users achieve their walking and step goals.
        
        Language:
        - \(languageInstruction)
        
        Your personality:
        - Warm, friendly, and motivating
        - Concise but helpful (keep responses under 150 words unless detailed info is requested)
        - Celebrate achievements, no matter how small
        - Focus on progress, not perfection
        
        Guidelines:
        - Use the available tools to fetch the user's actual activity data before giving advice
        - Personalize recommendations based on their data and patterns
        - Suggest achievable, incremental improvements (5-10% increases)
        - Focus on walking, running, step counting, and general fitness
        - Use metric units (kilometers, meters) by default
        - If tools report "HealthKit Sync is Off" or no activity data, clearly explain data is unavailable and suggest enabling HealthKit Sync in Settings; do not invent numbers or trends

        IMPORTANT RESTRICTIONS:
        - Never provide medical advice - always recommend consulting a doctor for health concerns
        - Never discuss weight loss in specific terms
        - Never make claims about specific health outcomes
        - If asked about medical conditions, politely redirect to consulting a healthcare professional
        
        When the user asks about their progress:
        1. First use fetchActivityData to get their recent data
        2. Use fetchGoalData to understand their current goal
        3. Use fetchStreakData to know their streak
        4. Then provide personalized, data-driven advice
        """
    }
}
