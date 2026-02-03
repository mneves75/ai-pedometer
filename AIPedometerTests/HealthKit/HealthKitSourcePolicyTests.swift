import Testing
import Foundation
@testable import AIPedometer

@Suite("HealthKitSourcePolicy Tests")
struct HealthKitSourcePolicyTests {
    @Test("Detects Apple Watch priority from product type")
    func watchPriorityFromProductType() {
        let sample = makeSample(productType: "Watch6,1")

        let priority = HealthKitSourcePolicy.priority(for: sample)

        #expect(priority == .watch)
    }

    @Test("Detects iPhone priority from product type")
    func phonePriorityFromProductType() {
        let sample = makeSample(productType: "iPhone16,2")

        let priority = HealthKitSourcePolicy.priority(for: sample)

        #expect(priority == .phone)
    }

    @Test("Falls back to Apple-other for Apple bundle identifiers")
    func appleOtherPriorityForAppleBundle() {
        let sample = makeSample(bundleIdentifier: "com.apple.health")

        let priority = HealthKitSourcePolicy.priority(for: sample)

        #expect(priority == .appleOther)
    }

    @Test("Uses third-party priority for non-Apple bundles")
    func thirdPartyPriority() {
        let sample = makeSample(bundleIdentifier: "com.thirdparty.pedometer")

        let priority = HealthKitSourcePolicy.priority(for: sample)

        #expect(priority == .thirdParty)
    }

    @Test("Detects Apple Watch priority from device model")
    func watchPriorityFromDeviceModel() {
        let sample = makeSample(deviceModel: "Apple Watch Series 9")

        let priority = HealthKitSourcePolicy.priority(for: sample)

        #expect(priority == .watch)
    }

    @Test("Detects iPhone priority from device name")
    func phonePriorityFromDeviceName() {
        let sample = makeSample(deviceName: "iPhone de Marcus")

        let priority = HealthKitSourcePolicy.priority(for: sample)

        #expect(priority == .phone)
    }

    private func makeSample(
        bundleIdentifier: String? = nil,
        productType: String? = nil,
        deviceModel: String? = nil,
        deviceName: String? = nil
    ) -> HealthKitSampleValue {
        HealthKitSampleValue(
            start: Date(timeIntervalSinceReferenceDate: 0),
            end: Date(timeIntervalSinceReferenceDate: 1),
            value: 1,
            sourceBundleIdentifier: bundleIdentifier,
            productType: productType,
            deviceModel: deviceModel,
            deviceName: deviceName
        )
    }
}
