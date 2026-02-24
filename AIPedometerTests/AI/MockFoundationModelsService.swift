import Foundation
import FoundationModels
@testable import AIPedometer

@MainActor
final class MockFoundationModelsService: FoundationModelsServiceProtocol {
    var availability: AIModelAvailability = .available

    var respondResult: Result<Any, AIServiceError> = .failure(.sessionNotConfigured)
    var respondStringResult: Result<String, AIServiceError> = .failure(.sessionNotConfigured)
    var respondCallCount = 0
    var lastPrompt: String?
    var respondDelayNanoseconds: UInt64 = 0

    func checkAvailability() -> AIModelAvailability {
        availability
    }

    func respond(to prompt: String) async throws(AIServiceError) -> String {
        respondCallCount += 1
        lastPrompt = prompt
        if respondDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: respondDelayNanoseconds)
        }

        switch respondStringResult {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    func respond<T: Generable>(to prompt: String, as type: T.Type) async throws(AIServiceError) -> T {
        respondCallCount += 1
        lastPrompt = prompt
        if respondDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: respondDelayNanoseconds)
        }

        switch respondResult {
        case .success(let value):
            guard let typed = value as? T else {
                throw AIServiceError.invalidResponse
            }
            return typed
        case .failure(let error):
            throw error
        }
    }
}
