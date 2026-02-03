import Foundation

enum HealthKitSourcePolicy {
    enum Priority: Int, CaseIterable, Comparable, Sendable {
        case watch = 3
        case phone = 2
        case appleOther = 1
        case thirdParty = 0

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private static let appleBundlePrefix = "com.apple."
    private static let watchPrefix = "watch"
    private static let iphonePrefix = "iphone"
    private static let ipodPrefix = "ipod"
    private static let ipadPrefix = "ipad"

    static func priority(for sample: HealthKitSampleValue) -> Priority {
        priority(
            bundleIdentifier: sample.sourceBundleIdentifier,
            productType: sample.productType,
            deviceModel: sample.deviceModel,
            deviceName: sample.deviceName
        )
    }

    static func priority(
        bundleIdentifier: String?,
        productType: String?,
        deviceModel: String?,
        deviceName: String?
    ) -> Priority {
        if isWatchProductType(productType) || isWatchDevice(model: deviceModel, name: deviceName) {
            return .watch
        }
        if isPhoneProductType(productType) || isPhoneDevice(model: deviceModel, name: deviceName) {
            return .phone
        }
        if isAppleBundleIdentifier(bundleIdentifier) {
            return .appleOther
        }
        return .thirdParty
    }

    static func isAppleBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return bundleIdentifier.hasPrefix(appleBundlePrefix)
    }

    private static func isWatchProductType(_ productType: String?) -> Bool {
        guard let token = normalized(productType) else { return false }
        return token.hasPrefix(watchPrefix)
    }

    private static func isPhoneProductType(_ productType: String?) -> Bool {
        guard let token = normalized(productType) else { return false }
        return token.hasPrefix(iphonePrefix) || token.hasPrefix(ipodPrefix)
    }

    private static func isWatchDevice(model: String?, name: String?) -> Bool {
        guard let token = normalized(model) ?? normalized(name) else { return false }
        return token.contains(watchPrefix)
    }

    private static func isPhoneDevice(model: String?, name: String?) -> Bool {
        guard let token = normalized(model) ?? normalized(name) else { return false }
        return token.contains(iphonePrefix) || token.contains(ipodPrefix) || token.contains(ipadPrefix)
    }

    private static func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
