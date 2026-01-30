import Foundation
import SwiftData

enum ModelMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum SchemaV1: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(1, 0, 0)
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
