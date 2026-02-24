import CryptoKit
import Foundation

/// Errors that can occur when using AI services
enum AIServiceError: Error, Sendable {
    case sessionNotConfigured
    case modelUnavailable(AIUnavailabilityReason)
    case generationFailed(underlying: String)
    case tokenLimitExceeded
    case guardrailViolation
    case invalidResponse
}

/// Reasons why the AI model may be unavailable
enum AIUnavailabilityReason: String, Sendable, Equatable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown
    
    var userFacingMessage: String {
        switch self {
        case .deviceNotEligible:
            return L10n.localized("Your device doesn't support Apple Intelligence", comment: "AI unavailable - device not eligible")
        case .appleIntelligenceNotEnabled:
            return L10n.localized("Enable Apple Intelligence in Settings to use AI features", comment: "AI unavailable - not enabled")
        case .modelNotReady:
            return L10n.localized("AI model is being prepared. Please try again later.", comment: "AI unavailable - model not ready")
        case .unknown:
            return L10n.localized("AI features are temporarily unavailable", comment: "AI unavailable - unknown reason")
        }
    }
    
    var hasAction: Bool {
        self == .appleIntelligenceNotEnabled
    }
    
    var actionTitle: String {
        L10n.localized("Open Settings", comment: "Button to open Settings app")
    }
}

extension AIServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .sessionNotConfigured:
            return L10n.localized("AI session not configured", comment: "Error - session not configured")
        case .modelUnavailable(let reason):
            return reason.userFacingMessage
        case .generationFailed:
            return L10n.localized("AI generation failed. Please try again.", comment: "Error - generation failed")
        case .tokenLimitExceeded:
            return L10n.localized("The conversation is too long. Please start a new conversation.", comment: "Error - token limit exceeded")
        case .guardrailViolation:
            return L10n.localized("The request could not be processed due to content restrictions.", comment: "Error - guardrail violation")
        case .invalidResponse:
            return L10n.localized("Received an invalid response from the AI model.", comment: "Error - invalid response")
        }
    }
}

extension AIServiceError {
    var partialResponseNotice: String {
        switch self {
        case .generationFailed:
            return String(
                localized: "The response was interrupted and may be incomplete. Try again to continue.",
                comment: "Inline warning for partial AI response interrupted by generation failure"
            )
        case .tokenLimitExceeded:
            return String(
                localized: "The response hit the conversation limit and may be incomplete. Start a new conversation to continue.",
                comment: "Inline warning for partial AI response interrupted by token/context limit"
            )
        default:
            return localizedDescription
        }
    }

    var logDescription: String {
        switch self {
        case .generationFailed(let underlying):
            return "AI generation failed [ref:\(Self.errorFingerprint(for: underlying))]"
        default:
            return localizedDescription
        }
    }

    private static func errorFingerprint(for message: String) -> String {
        let digest = SHA256.hash(data: Data(message.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(12))
    }
}
