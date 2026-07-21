import Foundation
import FoundationModels
import Testing

@testable import AIPedometer

@Suite("AIServiceError Tests")
struct AIServiceErrorTests {
    @Test("Generation errors map identically in both AI services")
    @MainActor
    func generationErrorsMapIdentically() {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
        let cases: [(LanguageModelSession.GenerationError, ExpectedAIError)] = [
            (.exceededContextWindowSize(context), .tokenLimitExceeded),
            (.assetsUnavailable(context), .modelNotReady),
            (.guardrailViolation(context), .guardrailViolation),
            (.refusal(refusal, context), .guardrailViolation),
            (.unsupportedGuide(context), .invalidResponse),
            (.unsupportedLanguageOrLocale(context), .invalidResponse),
            (.decodingFailure(context), .invalidResponse),
            (.rateLimited(context), .retryableGenerationFailure),
            (.concurrentRequests(context), .retryableGenerationFailure)
        ]

        for (generationError, expected) in cases {
            let foundationError = FoundationModelsService.mapError(generationError)
            let coachError = CoachService.mapError(generationError)

            #expect(expected.matches(foundationError))
            #expect(expected.matches(coachError))
            #expect(foundationError.logDescription == coachError.logDescription)
        }
    }

    @Test("Non-generation errors retain the generic fallback")
    @MainActor
    func nonGenerationErrorUsesGenericFallback() {
        let error = MappingProbeError()

        #expect(ExpectedAIError.genericGenerationFailure.matches(FoundationModelsService.mapError(error)))
        #expect(ExpectedAIError.genericGenerationFailure.matches(CoachService.mapError(error)))
    }

    @Test("Token limit message is localized")
    func tokenLimitMessageIsLocalized() {
        let message = AIServiceError.tokenLimitExceeded.localizedDescription
        let expected = String(
            localized: "The conversation is too long. Please start a new conversation.",
            comment: "Error - token limit exceeded"
        )
        #expect(message == expected)
    }

    @Test("Guardrail message is localized")
    func guardrailMessageIsLocalized() {
        let message = AIServiceError.guardrailViolation.localizedDescription
        let expected = String(
            localized: "The request could not be processed due to content restrictions.",
            comment: "Error - guardrail violation"
        )
        #expect(message == expected)
    }

    @Test("Generation failed message is localized and hides underlying error")
    func generationFailedMessageIsLocalized() {
        let message = AIServiceError.generationFailed(underlying: "Socket closed").localizedDescription
        let expected = String(
            localized: "AI generation failed. Please try again.",
            comment: "Error - generation failed"
        )
        #expect(message == expected)
        #expect(!message.contains("Socket"))
    }

    @Test("Log description fingerprints underlying error")
    func logDescriptionFingerprintsUnderlyingError() {
        let error = AIServiceError.generationFailed(underlying: "Socket closed")
        let log = error.logDescription
        #expect(log.contains("AI generation failed"))
        #expect(log.contains("ref:"))
        #expect(!log.contains("Socket"))
    }

    @Test("Partial response notice is specific for generation failures")
    func partialResponseNoticeGenerationFailed() {
        let notice = AIServiceError.generationFailed(underlying: "Socket closed").partialResponseNotice
        let expected = String(
            localized: "The response was interrupted and may be incomplete. Try again to continue.",
            comment: "Inline warning for partial AI response interrupted by generation failure"
        )
        #expect(notice == expected)
    }

    @Test("Partial response notice is specific for token limit interruptions")
    func partialResponseNoticeTokenLimit() {
        let notice = AIServiceError.tokenLimitExceeded.partialResponseNotice
        let expected = String(
            localized: "The response hit the conversation limit and may be incomplete. Start a new conversation to continue.",
            comment: "Inline warning for partial AI response interrupted by token/context limit"
        )
        #expect(notice == expected)
    }
}

private struct MappingProbeError: Error, LocalizedError {
    var errorDescription: String? { "mapping probe" }
}

private enum ExpectedAIError {
    case tokenLimitExceeded
    case modelNotReady
    case guardrailViolation
    case invalidResponse
    case retryableGenerationFailure
    case genericGenerationFailure

    func matches(_ error: AIServiceError) -> Bool {
        switch (self, error) {
        case (.tokenLimitExceeded, .tokenLimitExceeded),
             (.guardrailViolation, .guardrailViolation),
             (.invalidResponse, .invalidResponse):
            true
        case (.modelNotReady, .modelUnavailable(.modelNotReady)):
            true
        case (.retryableGenerationFailure, .generationFailed(let underlying)):
            underlying == "Please try again in a moment"
        case (.genericGenerationFailure, .generationFailed(let underlying)):
            underlying == "mapping probe"
        default:
            false
        }
    }
}
