import Foundation
import os

struct AppLogger: Sendable {
    private let logger: Logger


    init(subsystem: String, category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    func info(_ event: String, metadata: [String: String] = [:]) {
        logger.info("\(render(event: event, level: "info", metadata: metadata))")
    }

    func warning(_ event: String, metadata: [String: String] = [:]) {
        logger.warning("\(render(event: event, level: "warning", metadata: metadata))")
    }

    func error(_ event: String, metadata: [String: String] = [:]) {
        logger.error("\(render(event: event, level: "error", metadata: metadata))")
    }

    private func render(event: String, level: String, metadata: [String: String]) -> String {
        Self.renderPayload(event: event, level: level, metadata: metadata, timestamp: .now)
    }

    static func renderPayload(
        event: String,
        level: String,
        metadata: [String: String],
        timestamp: Date
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var payload: [String: String] = [
            "event": event,
            "level": level,
            "timestamp": formatter.string(from: timestamp)
        ]
        for (key, value) in metadata {
            payload[key] = value
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            if let json = String(data: data, encoding: .utf8) {
                return json
            }
        } catch {
            // Avoid logging here to prevent recursive logger failures.
        }
        return "{\"event\":\"\(event)\",\"level\":\"\(level)\"}"
    }
}

enum Loggers {
    static let app = AppLogger(subsystem: AppConstants.bundleIdentifier, category: "app")
    static let health = AppLogger(subsystem: AppConstants.bundleIdentifier, category: "health")
    static let motion = AppLogger(subsystem: AppConstants.bundleIdentifier, category: "motion")
    static let tracking = AppLogger(subsystem: AppConstants.bundleIdentifier, category: "tracking")
    static let workouts = AppLogger(subsystem: AppConstants.bundleIdentifier, category: "workouts")
    static let badges = AppLogger(subsystem: AppConstants.bundleIdentifier, category: "badges")
    static let background = AppLogger(subsystem: AppConstants.bundleIdentifier, category: "background")
    static let widgets = AppLogger(subsystem: AppConstants.bundleIdentifier, category: "widgets")
    static let ai = AppLogger(subsystem: AppConstants.bundleIdentifier, category: "ai")
    static let sync = AppLogger(subsystem: AppConstants.bundleIdentifier, category: "sync")
}
