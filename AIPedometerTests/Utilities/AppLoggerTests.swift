import Foundation
import Testing

@testable import AIPedometer

struct AppLoggerTests {
    @Test("AppLogger renders JSON payload with metadata")
    func rendersPayloadWithMetadata() throws {
        let timestamp = Date(timeIntervalSince1970: 0)
        let payload = AppLogger.renderPayload(
            event: "test.event",
            level: "info",
            metadata: ["key": "value"],
            timestamp: timestamp
        )

        let data = try #require(payload.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
        let parsed = try #require(json)

        #expect(parsed["event"] == "test.event")
        #expect(parsed["level"] == "info")
        #expect(parsed["key"] == "value")
        #expect(parsed["timestamp"]?.contains("1970") == true)
    }
}
