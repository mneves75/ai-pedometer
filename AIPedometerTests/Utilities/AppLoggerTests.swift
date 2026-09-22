import Foundation
import Testing

@testable import AIPedometer

struct AppLoggerTests {
    @Test("AppLogger renders JSON payload with metadata")
    func rendersPayloadWithRedactedMetadata() throws {
        let timestamp = Date(timeIntervalSince1970: 0)
        let payload = AppLogger.renderPayload(
            event: "test.event",
            level: "info",
            metadata: ["path": "/private/app/container", "steps": "12000"],
            timestamp: timestamp
        )

        let data = try #require(payload.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
        let parsed = try #require(json)

        #expect(parsed["event"] == "test.event")
        #expect(parsed["level"] == "info")
        #expect(parsed["path"] == "[private]")
        #expect(parsed["steps"] == "[private]")
        #expect(parsed["timestamp"]?.contains("1970") == true)
        #expect(parsed["code"] == nil)
    }

    @Test("AppLogger renders the machine code verbatim while metadata stays redacted")
    func rendersCodeWithoutRedactingIt() throws {
        let payload = AppLogger.renderPayload(
            event: "premium.offerings_failed",
            level: "error",
            code: "CONFIGURATION_ERROR",
            metadata: ["error": "None of the products could be fetched", "code": "leaked"],
            timestamp: Date(timeIntervalSince1970: 0)
        )

        let data = try #require(payload.data(using: .utf8))
        let parsed = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])

        #expect(parsed["code"] == "CONFIGURATION_ERROR")
        #expect(parsed["error"] == "[private]")
    }

    @Test("AppLogger redacts a metadata key named code when no machine code is given")
    func redactsMetadataCodeWithoutExplicitCode() throws {
        let payload = AppLogger.renderPayload(
            event: "test.event",
            level: "error",
            metadata: ["code": "user supplied"],
            timestamp: Date(timeIntervalSince1970: 0)
        )

        let data = try #require(payload.data(using: .utf8))
        let parsed = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])

        #expect(parsed["code"] == "[private]")
    }
}
