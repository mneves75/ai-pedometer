import Foundation
import FoundationModels
import Observation

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    
    enum Role: String, Sendable {
        case user
        case assistant
    }
    
    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

@MainActor
@Observable
final class CoachService {
    private let foundationModelsService: FoundationModelsService
    private let healthKitService: any HealthKitServiceProtocol
    private let goalService: GoalService
    
    private var session: LanguageModelSession?
    
    private(set) var messages: [ChatMessage] = []
    private(set) var isGenerating = false
    private(set) var currentStreamedContent = ""
    private(set) var lastError: AIServiceError?
    
    static var suggestedQuestions: [String] {
        [
            String(localized: "How did I do this week?", comment: "Suggested AI Coach question about weekly performance"),
            String(localized: "What's my best day for walking?", comment: "Suggested AI Coach question about best walking day"),
            String(localized: "Should I increase my goal?", comment: "Suggested AI Coach question about increasing goal"),
            String(localized: "Create a plan to reach 10,000 steps", comment: "Suggested AI Coach question about creating a plan"),
            String(localized: "Why am I not hitting my goals?", comment: "Suggested AI Coach question about missing goals")
        ]
    }

    var suggestedQuestions: [String] {
        Self.suggestedQuestions
    }
    
    init(
        foundationModelsService: FoundationModelsService,
        healthKitService: any HealthKitServiceProtocol,
        goalService: GoalService
    ) {
        self.foundationModelsService = foundationModelsService
        self.healthKitService = healthKitService
        self.goalService = goalService
        
        configureSession()
    }
    
    func send(message: String) async {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isGenerating else { return }
        
        let userMessage = ChatMessage(role: .user, content: message)
        messages.append(userMessage)
        
        isGenerating = true
        currentStreamedContent = ""
        lastError = nil
        
        defer {
            isGenerating = false
            currentStreamedContent = ""
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
        
        do {
            let stream = session.streamResponse(to: message)
            var fullResponse = ""
            
            for try await partialResponse in stream {
                fullResponse = partialResponse.content
                currentStreamedContent = fullResponse
            }
            
            let assistantMessage = ChatMessage(role: .assistant, content: fullResponse)
            messages.append(assistantMessage)
            
            Loggers.ai.info("ai.coach_response_completed", metadata: [
                "message_length": "\(fullResponse.count)"
            ])
        } catch {
            let mappedError = mapError(error)
            lastError = mappedError
            
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
        messages.removeAll()
        configureSession()
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
        
        session = LanguageModelSession(
            tools: tools,
            instructions: Self.coachInstructions()
        )
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
