import Foundation
import FoundationModels
import Observation
import os

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
    private let systemAvailability: () -> SystemLanguageModel.Availability

    init(
        instructions: String = FoundationModelsService.defaultInstructions(),
        systemAvailability: @escaping () -> SystemLanguageModel.Availability = { SystemLanguageModel.default.availability }
    ) {
        self.instructions = instructions
        self.systemAvailability = systemAvailability
        if LaunchConfiguration.isUITesting() {
            self.availability = .unavailable(reason: .deviceNotEligible)
            self.session = nil
            return
        }
        self.availability = checkAvailability()
        if availability == .available {
            configureSession()
        }
        startObservingSystemAvailability()
    }

    // The OS value is not static: Apple Intelligence toggles, settings re-evaluation, and
    // model-asset downloads flip `SystemLanguageModel.availability` while the app is running
    // (proven on-device 2026-07-20, iOS 27: notEnabled → available without relaunch). The model
    // is Observation.Observable, so track it and re-publish through `refreshAvailability`;
    // snapshotting only at launch/foreground leaves the banner stuck on a stale reason.
    // The flag keeps re-arming single-flight: each fire disarms before the handler re-arms,
    // so direct handler calls (tests) can never accumulate registrations.
    private var isObservingSystemAvailability = false

    private func startObservingSystemAvailability() {
        guard !isObservingSystemAvailability else { return }
        isObservingSystemAvailability = true
        withObservationTracking {
            _ = SystemLanguageModel.default.availability
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObservingSystemAvailability = false
                self.handleSystemAvailabilityChange()
            }
        }
    }

    func handleSystemAvailabilityChange() {
        refreshAvailability()
        startObservingSystemAvailability()
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
        let currentAvailability = systemAvailability()
        // Public os_log on purpose: AppLogger redacts every metadata value by design, and this
        // device-state enum (no personal data) is the only signal that explained the iOS 27
        // stale-banner bug in a live syslog stream.
        os_log(.info, log: OSLog(subsystem: AppConstants.bundleIdentifier, category: "ai"),
               "ai.availability_check %{public}@", String(describing: currentAvailability))
        switch currentAvailability {
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
        guard case .available = availability else {
            throw unavailableError()
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
        guard case .available = availability else {
            throw unavailableError()
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

    private func unavailableError() -> AIServiceError {
        if let reason = availability.unavailabilityReason {
            return .modelUnavailable(reason)
        }
        return .sessionNotConfigured
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
