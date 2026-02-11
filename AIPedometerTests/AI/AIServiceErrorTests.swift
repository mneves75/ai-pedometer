import Testing

@testable import AIPedometer

@Suite("AIServiceError Tests")
struct AIServiceErrorTests {
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
