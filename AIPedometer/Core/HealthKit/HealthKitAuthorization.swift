import Foundation
import HealthKit
import Observation

enum HealthKitAuthStatus: String, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

@Observable
@MainActor
final class HealthKitAuthorization {
    private let healthStore = HKHealthStore()

    var status: HealthKitAuthStatus = .notDetermined

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func refreshStatus() {
        guard Self.isAvailable else {
            status = .unavailable
            return
        }

        let stepType = HKQuantityType(.stepCount)
        let auth = healthStore.authorizationStatus(for: stepType)
        switch auth {
        case .notDetermined:
            status = .notDetermined
        case .sharingAuthorized:
            status = .authorized
        case .sharingDenied:
            status = .denied
        @unknown default:
            status = .notDetermined
        }
    }

    func requestAuthorization() async throws {
        guard Self.isAvailable else {
            status = .unavailable
            throw HealthKitError.notAvailable
        }

        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.flightsClimbed),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
            HKQuantityType(.pushCount),
            HKObjectType.workoutType(),
            HKObjectType.activitySummaryType()
        ]

        let typesToWrite: Set<HKSampleType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
            HKWorkoutType.workoutType()
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            refreshStatus()
        } catch {
            Loggers.health.warning("healthkit.authorization_failed", metadata: [
                "error": error.localizedDescription
            ])
            status = .denied
            throw HealthKitError.authorizationFailed
        }
    }
}
