import Foundation
import SwiftData

@Model
final class AuditEvent {
    var timestamp: Date
    var event: String
    var success: Bool
    var requestID: String
    var sessionID: String
    var metadata: [String: String]
    var createdAt: Date
    var deletedAt: Date?

    init(
        event: String,
        success: Bool,
        requestID: String,
        sessionID: String,
        metadata: [String: String] = [:],
        timestamp: Date = .now,
        createdAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.event = event
        self.success = success
        self.requestID = requestID
        self.sessionID = sessionID
        self.metadata = metadata
        self.timestamp = timestamp
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}
