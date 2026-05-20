import Foundation
import HealthKit
import Testing

@testable import AIPedometer

@Suite("HealthKit authorization contract")
struct HealthKitAuthorizationTests {
    @Test("Requested read types include every activity metric the app displays")
    @MainActor
    func requestedReadTypesIncludeDisplayedMetrics() {
        let readTypes = HealthKitAuthorization.requestedReadTypes

        #expect(readTypes.contains(HKQuantityType(.stepCount)))
        #expect(readTypes.contains(HKQuantityType(.distanceWalkingRunning)))
        #expect(readTypes.contains(HKQuantityType(.flightsClimbed)))
        #expect(readTypes.contains(HKQuantityType(.activeEnergyBurned)))
        #expect(readTypes.contains(HKQuantityType(.heartRate)))
        #expect(readTypes.contains(HKQuantityType(.pushCount)))
        #expect(readTypes.contains(HKQuantityType(.distanceWheelchair)))
        #expect(readTypes.contains(HKObjectType.workoutType()))
    }

    @Test("Requested write types stay limited to workouts")
    @MainActor
    func requestedWriteTypesStayLimitedToWorkouts() {
        #expect(HealthKitAuthorization.requestedWriteTypes == [HKWorkoutType.workoutType()])
    }

    @Test("Privacy manifest declares Health and Fitness data categories")
    func privacyManifestDeclaresHealthAndFitnessCategories() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let collectedTypes = try #require(plist?["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let declaredTypes = Set(collectedTypes.compactMap { $0["NSPrivacyCollectedDataType"] as? String })

        #expect(declaredTypes.contains("NSPrivacyCollectedDataTypeHealth"))
        #expect(declaredTypes.contains("NSPrivacyCollectedDataTypeFitness"))
    }

    @Test("Health share usage copy names the read categories users grant")
    func healthShareUsageCopyNamesReadCategories() throws {
        let usageDescription = try #require(Bundle.main.object(
            forInfoDictionaryKey: "NSHealthShareUsageDescription"
        ) as? String)
        let lowercase = usageDescription.lowercased()

        #expect(lowercase.contains("steps") || lowercase.contains("passos"))
        #expect(lowercase.contains("wheelchair") || lowercase.contains("cadeira de rodas"))
        #expect(lowercase.contains("distance") || lowercase.contains("distância"))
        #expect(lowercase.contains("heart rate") || lowercase.contains("frequência cardíaca"))
    }
}
