import Foundation
import SwiftData

enum ModelMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
        ]
    }
}

enum SchemaV1: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(1, 0, 0)

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
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?

        init(
            typeRaw: String,
            startTime: Date,
            endTime: Date? = nil,
            steps: Int = 0,
            distance: Double = 0,
            activeCalories: Double = 0,
            routeData: Data? = nil,
            healthKitWorkoutID: UUID? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            deletedAt: Date? = nil
        ) {
            self.typeRaw = typeRaw
            self.startTime = startTime
            self.endTime = endTime
            self.steps = steps
            self.distance = distance
            self.activeCalories = activeCalories
            self.routeData = routeData
            self.healthKitWorkoutID = healthKitWorkoutID
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    static var models: [any PersistentModel.Type] {
        [
            DailyStepRecord.self,
            StepGoal.self,
            Streak.self,
            EarnedBadge.self,
            SchemaV1.WorkoutSession.self,
            TrainingPlanRecord.self,
            AuditEvent.self,
            AIContextSnapshot.self
        ]
    }
}

enum SchemaV2: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            DailyStepRecord.self,
            StepGoal.self,
            Streak.self,
            EarnedBadge.self,
            WorkoutSession.self,
            TrainingPlanRecord.self,
            AuditEvent.self,
            AIContextSnapshot.self
        ]
    }
}
