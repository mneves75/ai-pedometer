import Foundation

struct WatchPayload: Codable, Sendable {
    let senderID: UUID?
    let revision: UInt64?
    let todaySteps: Int
    let goalSteps: Int
    let goalProgress: Double
    let currentStreak: Int
    let lastUpdated: Date
    let weeklySteps: [Int]
    let sentAt: Date?
    /// What `todaySteps` counts. Payloads from a phone that predates this field decode as `.steps`.
    let activityMode: ActivityTrackingMode

    init(
        senderID: UUID? = nil,
        revision: UInt64? = nil,
        todaySteps: Int,
        goalSteps: Int,
        goalProgress: Double,
        currentStreak: Int,
        lastUpdated: Date,
        weeklySteps: [Int],
        sentAt: Date? = nil,
        activityMode: ActivityTrackingMode = .steps
    ) {
        self.senderID = senderID
        self.revision = revision
        self.todaySteps = todaySteps
        self.goalSteps = goalSteps
        self.goalProgress = goalProgress
        self.currentStreak = currentStreak
        self.lastUpdated = lastUpdated
        self.weeklySteps = weeklySteps
        self.sentAt = sentAt
        self.activityMode = activityMode
    }

    private enum CodingKeys: String, CodingKey {
        case senderID
        case revision
        case todaySteps
        case goalSteps
        case goalProgress
        case currentStreak
        case lastUpdated
        case weeklySteps
        case sentAt
        case activityMode
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        senderID = try container.decodeIfPresent(UUID.self, forKey: .senderID)
        revision = try container.decodeIfPresent(UInt64.self, forKey: .revision)
        todaySteps = try container.decode(Int.self, forKey: .todaySteps)
        goalSteps = try container.decode(Int.self, forKey: .goalSteps)
        goalProgress = try container.decode(Double.self, forKey: .goalProgress)
        currentStreak = try container.decode(Int.self, forKey: .currentStreak)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        weeklySteps = try container.decode([Int].self, forKey: .weeklySteps)
        sentAt = try container.decodeIfPresent(Date.self, forKey: .sentAt)
        // `try?`: a mode this build does not know (written by a newer phone) must not discard the whole snapshot.
        activityMode = (try? container.decodeIfPresent(ActivityTrackingMode.self, forKey: .activityMode)) ?? .steps
    }

    var deliveryOrder: Date {
        sentAt ?? lastUpdated
    }

    static func shouldAccept(_ candidate: WatchPayload, after latestAcceptedOrder: Date?) -> Bool {
        guard let latestAcceptedOrder else { return true }
        return candidate.deliveryOrder > latestAcceptedOrder
    }

    static let transferKey = "payload"

    static let placeholder = WatchPayload(
        todaySteps: 0,
        goalSteps: 10_000,
        goalProgress: 0,
        currentStreak: 0,
        lastUpdated: .now,
        weeklySteps: [],
        sentAt: nil
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

struct WatchPayloadAcceptanceState: Sendable {
    private(set) var senderID: UUID?
    private(set) var latestRevision: UInt64?
    private(set) var latestLegacyOrder: Date?
    private(set) var latestGlobalOrder: Date?
    private var retiredSenderIDs: Set<UUID> = []

    mutating func accept(_ candidate: WatchPayload) -> Bool {
        if let candidateSenderID = candidate.senderID,
           let candidateRevision = candidate.revision {
            if candidateSenderID == senderID {
                guard candidateRevision > (latestRevision ?? 0) else { return false }
            } else {
                guard !retiredSenderIDs.contains(candidateSenderID) else { return false }
                if let senderID {
                    guard candidate.deliveryOrder > (latestGlobalOrder ?? .distantPast) else {
                        return false
                    }
                    retiredSenderIDs.insert(senderID)
                }
                senderID = candidateSenderID
            }

            latestRevision = candidateRevision
            latestLegacyOrder = nil
            latestGlobalOrder = max(latestGlobalOrder ?? .distantPast, candidate.deliveryOrder)
            return true
        }

        guard senderID == nil else { return false }
        guard WatchPayload.shouldAccept(candidate, after: latestLegacyOrder) else { return false }
        latestLegacyOrder = candidate.deliveryOrder
        latestGlobalOrder = candidate.deliveryOrder
        return true
    }
}
