import Foundation
import os

struct AppLogger: Sendable {
    private let logger: Logger

    init(subsystem: String, category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    /// The event name and `code` are the only public parts of a line; the JSON payload stays
    /// private. Without that, a device log shows the whole entry as `<private>` (observed on the
    /// iMarcus on 2026-09-21) and no failure can be told apart outside a debugger. `code` is for
    /// enum-like machine codes only (for example `NSURLErrorDomain:-1009`);
    /// user input, health data, identifiers and free-form error text stay in `metadata`, which is
    /// always redacted. `event` is a `StaticString` so a name built from runtime data cannot reach
    /// the public part of the line.
    func info(_ event: StaticString, code: String? = nil, metadata: [String: String] = [:]) {
        let payload = render(event: event, level: "info", code: code, metadata: metadata)
        logger.info("\(event.description, privacy: .public) \(code ?? "-", privacy: .public) \(payload, privacy: .private)")
    }

    func warning(_ event: StaticString, code: String? = nil, metadata: [String: String] = [:]) {
        let payload = render(event: event, level: "warning", code: code, metadata: metadata)
        logger.warning("\(event.description, privacy: .public) \(code ?? "-", privacy: .public) \(payload, privacy: .private)")
    }

    func error(_ event: StaticString, code: String? = nil, metadata: [String: String] = [:]) {
        let payload = render(event: event, level: "error", code: code, metadata: metadata)
        logger.error("\(event.description, privacy: .public) \(code ?? "-", privacy: .public) \(payload, privacy: .private)")
    }

    private func render(event: StaticString, level: String, code: String?, metadata: [String: String]) -> String {
        Self.renderPayload(event: event.description, level: level, code: code, metadata: metadata, timestamp: .now)
    }

    // Apple documents ISO8601DateFormatter as thread-safe, so sharing one instance across threads is sound despite the missing Sendable annotation.
    nonisolated(unsafe) private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func renderPayload(
        event: String,
        level: String,
        code: String? = nil,
        metadata: [String: String],
        timestamp: Date
    ) -> String {
        var payload: [String: String] = [
            "event": event,
            "level": level,
            "timestamp": iso8601Formatter.string(from: timestamp)
        ]
        for key in metadata.keys {
            payload[key] = "[private]"
        }
        if let code {
            payload["code"] = code
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
