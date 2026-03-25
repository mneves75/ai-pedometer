import Foundation
import RevenueCat
import Testing

@testable import AIPedometer

@MainActor
final class FakePurchasesClient: PurchasesClientProtocol {
    var configured = false
    var configureCallCount = 0
    var configureAPIKey: String?

    var offeringsResult: Result<Offerings, any Error> = .failure(CocoaError(.fileNoSuchFile))
    var customerInfoResult: Result<CustomerInfo, any Error> = .failure(CocoaError(.fileNoSuchFile))
    var restoreResult: Result<CustomerInfo, any Error> = .failure(CocoaError(.fileNoSuchFile))
    var syncResult: Result<CustomerInfo, any Error> = .failure(CocoaError(.fileNoSuchFile))
    var purchaseResult: Result<PremiumPurchaseResult, any Error> = .failure(CocoaError(.fileNoSuchFile))
    var showManageSubscriptionsResult: Result<Void, any Error> = .success(())
    var streamedCustomerInfo: [CustomerInfo] = []
    var customerInfoDelayNanoseconds: UInt64 = 0

    func isConfigured() -> Bool {
        configured
    }

    func configure(apiKey: String) {
        configureCallCount += 1
        configureAPIKey = apiKey
        configured = true
    }

    func offerings() async throws -> Offerings {
        return try offeringsResult.get()
    }

    func customerInfo() async throws -> CustomerInfo {
        if customerInfoDelayNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: customerInfoDelayNanoseconds)
            } catch {
                // Ignore cancellation in the fake client; tests control lifecycle explicitly.
            }
        }
        return try customerInfoResult.get()
    }

    func restorePurchases() async throws -> CustomerInfo {
        return try restoreResult.get()
    }

    func syncPurchases() async throws -> CustomerInfo {
        return try syncResult.get()
    }

    func purchase(package: Package) async throws -> PremiumPurchaseResult {
        return try purchaseResult.get()
    }

    func showManageSubscriptions() async throws {
        switch showManageSubscriptionsResult {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    func customerInfoStream() -> AsyncStream<CustomerInfo> {
        let infos = streamedCustomerInfo
        return AsyncStream { continuation in
            Task { @MainActor in
                for info in infos {
                    continuation.yield(info)
                }
                continuation.finish()
            }
        }
    }
}

@MainActor
struct PremiumAccessStoreTests {
    @Test("prepare sets notConfigured when RevenueCat values are missing")
    func prepareSetsNotConfiguredWhenConfigurationMissing() async {
        let client = FakePurchasesClient()
        let store = PremiumAccessStore(
            configuration: .init(apiKey: nil, entitlementID: "premium", offeringID: nil),
            forcedPremiumEnabled: nil,
            isTesting: false,
            purchasesClient: client
        )

        await store.prepare()

        #expect(store.state == .notConfigured)
        #expect(store.canAccessAIFeatures == false)
        #expect(client.configureCallCount == 0)
    }

    @Test("prepare resolves access while customer info is loading")
    func prepareMarksResolvingAccessUntilCustomerInfoArrives() async {
        let client = FakePurchasesClient()
        let customerInfo = makeCustomerInfo(activeEntitlementIDs: ["premium"])
        client.customerInfoResult = .success(customerInfo)
        client.offeringsResult = .failure(CocoaError(.fileReadUnknown))
        client.customerInfoDelayNanoseconds = 50_000_000

        let store = PremiumAccessStore(
            configuration: .init(apiKey: "appl_test_key", entitlementID: "premium", offeringID: nil),
            forcedPremiumEnabled: nil,
            isTesting: false,
            purchasesClient: client
        )

        #expect(store.isResolvingAccess == true)
        let task = Task { await store.prepare() }
        await Task.yield()
        #expect(store.isResolvingAccess == true)
        await task.value

        #expect(store.state == .ready)
        #expect(store.canAccessAIFeatures == true)
        #expect(store.lastError != nil)
    }

    @Test("refresh preserves premium access when customer info succeeds and offerings fail")
    func refreshPreservesAccessWhenOfferingsFail() async {
        let client = FakePurchasesClient()
        client.customerInfoResult = .success(makeCustomerInfo(activeEntitlementIDs: ["premium"]))
        client.offeringsResult = .failure(URLError(.networkConnectionLost))

        let store = PremiumAccessStore(
            configuration: .init(apiKey: "appl_test_key", entitlementID: "premium", offeringID: nil),
            forcedPremiumEnabled: nil,
            isTesting: false,
            purchasesClient: client
        )

        await store.refresh()

        #expect(store.state == .ready)
        #expect(store.canAccessAIFeatures == true)
        #expect(store.lastError?.isEmpty == false)
    }

    @Test("showManageSubscriptions falls back to management URL")
    func showManageSubscriptionsFallsBackToManagementURL() async throws {
        let client = FakePurchasesClient()
        client.showManageSubscriptionsResult = .failure(CocoaError(.fileReadUnknown))
        let managementURL = try #require(URL(string: "https://apps.apple.com/account/subscriptions"))
        client.customerInfoResult = .success(
            makeCustomerInfo(activeEntitlementIDs: ["premium"], managementURL: managementURL)
        )

        let store = PremiumAccessStore(
            configuration: .init(apiKey: "appl_test_key", entitlementID: "premium", offeringID: nil),
            forcedPremiumEnabled: nil,
            isTesting: false,
            purchasesClient: client
        )
        await store.refresh()

        let didOpen = await store.showManageSubscriptions()

        #expect(didOpen == true)
        #expect(store.lastError == nil)
    }

    @Test("restore unlocks premium when a single active entitlement uses the dashboard name instead of the local fallback id")
    func restoreUnlocksPremiumForSingleActiveEntitlementAlias() async {
        let client = FakePurchasesClient()
        client.restoreResult = .success(
            makeCustomerInfo(activeEntitlementIDs: ["AI Pedometer Pro"])
        )

        let store = PremiumAccessStore(
            configuration: .init(apiKey: "appl_test_key", entitlementID: "premium", offeringID: nil),
            forcedPremiumEnabled: nil,
            isTesting: false,
            purchasesClient: client
        )

        await store.restorePurchases()

        #expect(store.state == .ready)
        #expect(store.canAccessAIFeatures == true)
    }

    @Test("restore unlocks premium when RevenueCat returns a known premium product id but no matching entitlement slug")
    func restoreUnlocksPremiumForKnownPremiumProductWithoutEntitlementSlug() async {
        let client = FakePurchasesClient()
        client.restoreResult = .success(
            makeCustomerInfo(
                activeEntitlementIDs: [],
                activeProductIDs: ["com.mneves.aipedometer.premium.yearly"],
                purchasedProductIDs: ["com.mneves.aipedometer.premium.yearly"]
            )
        )

        let store = PremiumAccessStore(
            configuration: .init(apiKey: "appl_test_key", entitlementID: "premium", offeringID: nil),
            forcedPremiumEnabled: nil,
            isTesting: false,
            purchasesClient: client
        )

        await store.restorePurchases()

        #expect(store.state == .ready)
        #expect(store.canAccessAIFeatures == true)
    }

    @Test("restore does not unlock premium for the tip jar product")
    func restoreDoesNotUnlockPremiumForTipJarProduct() async {
        let client = FakePurchasesClient()
        client.restoreResult = .success(
            makeCustomerInfo(
                activeEntitlementIDs: [],
                purchasedProductIDs: [AppConstants.TipJar.productID]
            )
        )

        let store = PremiumAccessStore(
            configuration: .init(apiKey: "appl_test_key", entitlementID: "premium", offeringID: nil),
            forcedPremiumEnabled: nil,
            isTesting: false,
            purchasesClient: client
        )

        await store.restorePurchases()

        #expect(store.state == .ready)
        #expect(store.canAccessAIFeatures == false)
    }
}

private func makeCustomerInfo(
    activeEntitlementIDs: Set<String>,
    activeProductIDs: Set<String> = [],
    purchasedProductIDs: Set<String> = [],
    managementURL: URL? = nil
) -> CustomerInfo {
    let entitlements = activeEntitlementIDs.reduce(into: [String: EntitlementInfo]()) { partialResult, identifier in
        partialResult[identifier] = EntitlementInfo(
            identifier: identifier,
            isActive: true,
            willRenew: true,
            periodType: .normal,
            latestPurchaseDate: .now,
            originalPurchaseDate: .now,
            expirationDate: .now.addingTimeInterval(86_400),
            store: .appStore,
            productIdentifier: "com.mneves.aipedometer.\(identifier)",
            isSandbox: true,
            ownershipType: .purchased,
            verification: .verified
        )
    }

    let activeProducts = activeProductIDs.union(
        activeEntitlementIDs.map { "com.mneves.aipedometer.\($0)" }
    )
    let purchasedProducts = purchasedProductIDs.union(activeProducts)

    return CustomerInfo(
        entitlements: EntitlementInfos(entitlements: entitlements, verification: .verified),
        expirationDatesByProductId: Dictionary(uniqueKeysWithValues: activeProducts.map {
            ($0, Date.now.addingTimeInterval(86_400))
        }),
        purchaseDatesByProductId: Dictionary(uniqueKeysWithValues: purchasedProducts.map {
            ($0, Date.now)
        }),
        allPurchasedProductIds: purchasedProducts,
        requestDate: .now,
        firstSeen: .now,
        originalAppUserId: "test-user",
        managementURL: managementURL
    )
}
