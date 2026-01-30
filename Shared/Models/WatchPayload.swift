import Foundation

struct WatchPayload: Codable, Sendable {
    let todaySteps: Int
    let goalSteps: Int
    let goalProgress: Double
    let currentStreak: Int
    let lastUpdated: Date
    let weeklySteps: [Int]

    static let transferKey = "payload"

    static let placeholder = WatchPayload(
        todaySteps: 0,
        goalSteps: 10_000,
        goalProgress: 0,
        currentStreak: 0,
        lastUpdated: .now,
        weeklySteps: []
    )

    static func decode(from data: Data?) -> WatchPayload? {
        guard let data else { return nil }
        do {
            return try JSONDecoder().decode(WatchPayload.self, from: data)
        } catch {
            Loggers.sync.error("watch_payload_decode_failed", metadata: [
                "error": error.localizedDescription
            ])
            return nil
        }
    }
}
