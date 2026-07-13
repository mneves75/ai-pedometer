import Foundation
import SwiftData

enum HealthKitWorkoutExportState: String, Codable, Sendable {
    case notRequired
    case pending
    case exported
}

@Model
final class WorkoutSession {
    var typeRaw: String
    var startTime: Date
    var endTime: Date?
    var steps: Int
    var distance: Double
    var activeCalories: Double
    var routeData: Data?
    var healthKitWorkoutID: UUID?
    /// Optional backing fields keep the schema change lightweight for existing 0.91 stores.
    /// A missing state belongs to a legacy row and resolves fail-safe to `.notRequired`.
    var healthKitExportStateRaw: String?
    var healthKitExportIdentifier: UUID?
    var healthKitExportFailureCountValue: Int?
    var healthKitExportLastFailureAt: Date?
    var healthKitExportLastErrorCode: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        type: WorkoutType,
        startTime: Date,
        endTime: Date? = nil,
        steps: Int = 0,
        distance: Double = 0,
        activeCalories: Double = 0,
        routeData: Data? = nil,
        healthKitWorkoutID: UUID? = nil,
        healthKitExportState: HealthKitWorkoutExportState? = nil,
        healthKitExportIdentifier: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.typeRaw = type.rawValue
        self.startTime = startTime
        self.endTime = endTime
        self.steps = steps
        self.distance = distance
        self.activeCalories = activeCalories
        self.routeData = routeData
        self.healthKitWorkoutID = healthKitWorkoutID
        self.healthKitExportStateRaw = (
            healthKitExportState ?? (endTime == nil ? .notRequired : .pending)
        ).rawValue
        self.healthKitExportIdentifier = healthKitExportIdentifier
        self.healthKitExportFailureCountValue = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var type: WorkoutType {
        WorkoutType(rawValue: typeRaw) ?? .outdoorWalk
    }

    var healthKitExportState: HealthKitWorkoutExportState {
        get {
            if healthKitWorkoutID != nil { return .exported }
            guard let raw = healthKitExportStateRaw else { return .notRequired }
            return HealthKitWorkoutExportState(rawValue: raw) ?? .notRequired
        }
        set { healthKitExportStateRaw = newValue.rawValue }
    }

    var healthKitExportFailureCount: Int {
        get { healthKitExportFailureCountValue ?? 0 }
        set { healthKitExportFailureCountValue = newValue }
    }

    var stableHealthKitExportIdentifier: UUID {
        if let healthKitExportIdentifier { return healthKitExportIdentifier }
        let identifier = UUID()
        healthKitExportIdentifier = identifier
        return identifier
    }
}
