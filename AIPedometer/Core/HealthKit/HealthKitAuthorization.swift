import Foundation
import HealthKit
import Observation

/// HealthKit does not provide a reliable "read permission granted/denied" state.
/// Industry-standard approach:
/// - Track whether the system *should* show the authorization prompt again.
/// - Attempt queries; if results are empty, guide the user to Settings.
enum HealthKitAccessStatus: String, Sendable {
    /// Health data is not available on this device.
    case unavailable
    /// The app should request authorization (prompt not shown yet for the requested types).
    case shouldRequest
    /// The app already requested authorization at least once (user may have granted or denied).
    case requested
}

@Observable
@MainActor
final class HealthKitAuthorization {
    private let healthStore: HKHealthStore

    var status: HealthKitAccessStatus = .shouldRequest

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func refreshStatus() async {
        guard Self.isAvailable else {
            status = .unavailable
            return
        }

        // Use Apple's request status API to know whether the authorization prompt
        // should be displayed again. This is not a "read permission granted" signal.
        do {
            let requestStatus = try await authorizationRequestStatus()
            switch requestStatus {
            case .shouldRequest:
                status = .shouldRequest
            case .unnecessary:
                status = .requested
            case .unknown:
                status = .requested
            @unknown default:
                status = .requested
            }
        } catch {
            Loggers.health.warning("healthkit.request_status_failed", metadata: [
                "error": error.localizedDescription
            ])
            // Conservatively treat as already requested; the UI should guide users to Settings.
            status = .requested
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
            HKQuantityType(.pushCount),
            HKObjectType.workoutType()
        ]

        // Only request write permissions for what we actually write.
        let typesToWrite: Set<HKSampleType> = [HKWorkoutType.workoutType()]

        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            await refreshStatus()
        } catch {
            Loggers.health.warning("healthkit.authorization_failed", metadata: [
                "error": error.localizedDescription
            ])
            // If authorization request fails, the next step is to guide the user to Settings.
            status = .requested
            throw HealthKitError.authorizationFailed
        }
    }

    private func authorizationRequestStatus() async throws -> HKAuthorizationRequestStatus {
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.flightsClimbed),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.pushCount),
            HKObjectType.workoutType()
        ]

        let typesToWrite: Set<HKSampleType> = [HKWorkoutType.workoutType()]

        return try await withCheckedThrowingContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: typesToWrite, read: typesToRead) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: status)
            }
        }
    }
}
