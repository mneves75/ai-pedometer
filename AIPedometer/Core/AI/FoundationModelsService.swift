import Foundation
import FoundationModels
import Observation

@MainActor
protocol FoundationModelsServiceProtocol: Sendable {
    var availability: AIModelAvailability { get }
    func checkAvailability() -> AIModelAvailability
    func respond(to prompt: String) async throws(AIServiceError) -> String
    func respond<T: Generable>(to prompt: String, as type: T.Type) async throws(AIServiceError) -> T
}

enum AIModelAvailability: Equatable, Sendable {
    case checking
    case available
    case unavailable(reason: AIUnavailabilityReason)
    
    var isAvailable: Bool {
        self == .available
    }
    
    var unavailabilityReason: AIUnavailabilityReason? {
        if case .unavailable(let reason) = self {
            return reason
        }
        return nil
    }
}

@MainActor
@Observable
final class FoundationModelsService: FoundationModelsServiceProtocol {
    private var session: LanguageModelSession?
    private(set) var availability: AIModelAvailability = .checking
    
    private let instructions: String
    
    init(instructions: String = FoundationModelsService.defaultInstructions()) {
        self.instructions = instructions
        if LaunchConfiguration.isUITesting() {
            self.availability = .unavailable(reason: .deviceNotEligible)
            self.session = nil
            return
        }
        self.availability = checkAvailability()
        if availability == .available {
            configureSession()
        }
    }

    func refreshAvailability() {
        if LaunchConfiguration.isUITesting() {
            availability = .unavailable(reason: .deviceNotEligible)
            session = nil
            return
        }
        let updatedAvailability = checkAvailability()
        if updatedAvailability != availability {
            availability = updatedAvailability
        }
        if availability == .available {
            configureSession()
        } else {
            session = nil
        }
    }
    
    func checkAvailability() -> AIModelAvailability {
        if LaunchConfiguration.isUITesting() {
            return .unavailable(reason: .deviceNotEligible)
        }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            let mappedReason: AIUnavailabilityReason = switch reason {
            case .deviceNotEligible:
                .deviceNotEligible
            case .appleIntelligenceNotEnabled:
                .appleIntelligenceNotEnabled
            case .modelNotReady:
                .modelNotReady
            @unknown default:
                .unknown
            }
            return .unavailable(reason: mappedReason)
        }
    }
    
    func respond(to prompt: String) async throws(AIServiceError) -> String {
        guard availability == .available else {
            throw AIServiceError.sessionNotConfigured
        }

        let oneShotSession = LanguageModelSession(instructions: instructions)
        do {
            let response = try await oneShotSession.respond(to: prompt)
            Loggers.ai.info("ai.response_generated", metadata: ["prompt_length": "\(prompt.count)"])
            return response.content
        } catch {
            Loggers.ai.error("ai.response_failed", metadata: ["error": error.localizedDescription])
            throw mapError(error)
        }
    }
    
    func respond<T: Generable>(to prompt: String, as type: T.Type) async throws(AIServiceError) -> T {
        guard availability == .available else {
            throw AIServiceError.sessionNotConfigured
        }

        let oneShotSession = LanguageModelSession(instructions: instructions)
        do {
            let response: LanguageModelSession.Response<T> = try await oneShotSession.respond(
                to: prompt,
                generating: type
            )
            Loggers.ai.info("ai.structured_response_generated", metadata: [
                "type": String(describing: type),
                "prompt_length": "\(prompt.count)"
            ])
            return response.content
        } catch {
            Loggers.ai.error("ai.structured_response_failed", metadata: [
                "type": String(describing: type),
                "error": error.localizedDescription
            ])
            throw mapError(error)
        }
    }
    
    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                guard let session = self.session else {
                    continuation.finish(throwing: AIServiceError.sessionNotConfigured)
                    return
                }
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
                    Loggers.ai.info("ai.stream_completed", metadata: ["prompt_length": "\(prompt.count)"])
                } catch {
                    Loggers.ai.error("ai.stream_failed", metadata: ["error": error.localizedDescription])
                    continuation.finish(throwing: mapError(error))
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    func configure(with tools: [any Tool]) {
        session = LanguageModelSession(
            tools: tools,
            instructions: instructions
        )
        Loggers.ai.info("ai.session_configured", metadata: ["tool_count": "\(tools.count)"])
    }
    
    private func configureSession() {
        session = LanguageModelSession(instructions: instructions)
        Loggers.ai.info("ai.session_initialized")
    }
    
    private func mapError(_ error: any Error) -> AIServiceError {
        if let sessionError = error as? LanguageModelSession.GenerationError {
            switch sessionError {
            case .exceededContextWindowSize:
                return .tokenLimitExceeded
            case .guardrailViolation, .refusal:
                return .guardrailViolation
            case .assetsUnavailable:
                return .modelUnavailable(.modelNotReady)
            case .unsupportedGuide, .unsupportedLanguageOrLocale, .decodingFailure:
                return .invalidResponse
            case .rateLimited, .concurrentRequests:
                return .generationFailed(underlying: "Please try again in a moment")
            @unknown default:
                return .generationFailed(underlying: error.localizedDescription)
            }
        }
        return .generationFailed(underlying: error.localizedDescription)
    }
}

extension FoundationModelsService {
    static func defaultInstructions(
        languageInstruction: String = AppLanguage.promptInstruction()
    ) -> String {
        """
        You are a supportive fitness coach helping users achieve their walking and activity goals.
        
        Language:
        - \(languageInstruction)
        
        Guidelines:
        - Be encouraging, positive, and concise
        - Use data from tools to personalize advice when available
        - Keep responses under 100 words unless detailed information is requested
        - Suggest achievable, incremental improvements
        - Never provide medical advice - recommend consulting a doctor for health concerns
        - Avoid weight-loss promises or numbers; keep weight-management guidance general
        - Do not claim specific health outcomes or diagnose conditions
        - Focus on walking, running, step counting, and general fitness
        - Use metric units (kilometers, meters) unless the user specifies otherwise
        """
    }
}
