import Foundation
import RevenueCat
import Testing

@testable import AIPedometer

@MainActor
final class FakePurchasesClient: PurchasesClientProtocol {
    var configured = false
    var configureCallCount = 0
    var configureAPIKey: String?
    var syncCallCount = 0
    var purchaseCallCount = 0
    var purchasedPackageIdentifiers: [String] = []

    var offeringsResult: Result<Offerings, any Error> = .failure(CocoaError(.fileNoSuchFile))
    var customerInfoResult: Result<CustomerInfo, any Error> = .failure(CocoaError(.fileNoSuchFile))
    var restoreResult: Result<CustomerInfo, any Error> = .failure(CocoaError(.fileNoSuchFile))
    var syncResult: Result<CustomerInfo, any Error> = .failure(CocoaError(.fileNoSuchFile))
    var purchaseResult: Result<PremiumPurchaseResult, any Error> = .failure(CocoaError(.fileNoSuchFile))
    var showManageSubscriptionsResult: Result<Void, any Error> = .success(())
    var streamedCustomerInfo: [CustomerInfo] = []
    var customerInfoStreamOverride: AsyncStream<CustomerInfo>?
    var shouldSuspendCustomerInfo = false
    private(set) var customerInfoCallCount = 0
    private(set) var customerInfoStreamCallCount = 0
    private var customerInfoContinuation: CheckedContinuation<Void, Never>?
    var shouldSuspendFirstPurchase = false
    var verifiedUnfinishedProductIDs: Set<String> = []
    private var purchaseContinuation: CheckedContinuation<Void, Never>?

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
        customerInfoCallCount += 1
        if shouldSuspendCustomerInfo {
            await withCheckedContinuation { continuation in
                customerInfoContinuation = continuation
            }
        }
        return try customerInfoResult.get()
    }

    func resumeCustomerInfo() {
        customerInfoContinuation?.resume()
        customerInfoContinuation = nil
    }

    func restorePurchases() async throws -> CustomerInfo {
        return try restoreResult.get()
    }

    func syncPurchases() async throws -> CustomerInfo {
        syncCallCount += 1
        return try syncResult.get()
    }

    func purchase(package: Package) async throws -> PremiumPurchaseResult {
        purchaseCallCount += 1
        purchasedPackageIdentifiers.append(package.identifier)
        if shouldSuspendFirstPurchase, purchaseCallCount == 1 {
            await withCheckedContinuation { continuation in
                purchaseContinuation = continuation
            }
        }
        return try purchaseResult.get()
    }

    func resumePurchase() {
        purchaseContinuation?.resume()
        purchaseContinuation = nil
    }

    func hasVerifiedUnfinishedTransaction(productID: String) async -> Bool {
        verifiedUnfinishedProductIDs.contains(productID)
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
        customerInfoStreamCallCount += 1
        if let customerInfoStreamOverride {
            return customerInfoStreamOverride
        }
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

    @Test("testing mode without explicit override does not unlock premium")
    func testingModeWithoutExplicitOverrideDoesNotUnlockPremium() async {
        let client = FakePurchasesClient()
        let store = PremiumAccessStore(
            configuration: .init(apiKey: nil, entitlementID: "premium", offeringID: nil),
            forcedPremiumEnabled: nil,
            isTesting: true,
            purchasesClient: client
        )

        await store.prepare()

        #expect(store.state == .notConfigured)
        #expect(store.canAccessAIFeatures == false)
        #expect(client.configureCallCount == 0)
    }

    @Test("prepare resolves access while customer info is loading")
    func prepareMarksResolvingAccessUntilCustomerInfoArrives() async throws {
        let client = FakePurchasesClient()
        let customerInfo = makeCustomerInfo(activeEntitlementIDs: ["premium"])
        client.customerInfoResult = .success(customerInfo)
        client.offeringsResult = .failure(CocoaError(.fileReadUnknown))
        client.shouldSuspendCustomerInfo = true

        let store = PremiumAccessStore(
            configuration: .init(apiKey: "appl_test_key", entitlementID: "premium", offeringID: nil),
            forcedPremiumEnabled: nil,
            isTesting: false,
            purchasesClient: client
        )

        #expect(store.isResolvingAccess == true)
        let task = Task { await store.prepare() }
        defer { client.resumeCustomerInfo() }
        try await waitUntilPremiumCondition("RevenueCat customer info request did not start") {
            client.customerInfoCallCount == 1
        }
        #expect(store.isResolvingAccess == true)
        #expect(store.canAccessAIFeatures == false)
        client.resumeCustomerInfo()
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

    @Test("refresh rejects failed RevenueCat verification before publishing customer info")
    func refreshRejectsFailedVerificationBeforePublishingCustomerInfo() async {
        let client = FakePurchasesClient()
        client.customerInfoResult = .success(
            makeCustomerInfo(activeEntitlementIDs: ["premium"], verification: .failed)
        )

        let store = makePremiumAccessStore(client: client)

        await store.refresh()

        #expect(store.customerInfo == nil)
        #expect(store.canAccessAIFeatures == false)
        if case .unavailable = store.state {
            // Expected: failed verification must never become published access state.
        } else {
            Issue.record("Expected failed verification to make premium unavailable")
        }
    }

    @Test("refresh rejects customer info when RevenueCat verification was not requested")
    func refreshRejectsNotRequestedVerificationBeforePublishingCustomerInfo() async {
        let client = FakePurchasesClient()
        client.customerInfoResult = .success(
            makeCustomerInfo(activeEntitlementIDs: ["premium"], verification: .notRequested)
        )

        let store = makePremiumAccessStore(client: client)

        await store.refresh()

        #expect(store.customerInfo == nil)
        #expect(store.canAccessAIFeatures == false)
        if case .unavailable = store.state {
            // Expected: only positively verified customer info may grant access.
        } else {
            Issue.record("Expected unverified customer info to make premium unavailable")
        }
    }

    @Test("Cancelling prepare before customer info resolves remains fail closed")
    func cancellingPrepareBeforeCustomerInfoResolvesRemainsFailClosed() async throws {
        let client = FakePurchasesClient()
        client.customerInfoResult = .success(makeCustomerInfo(activeEntitlementIDs: ["premium"]))
        client.shouldSuspendCustomerInfo = true

        let store = PremiumAccessStore(
            configuration: .init(apiKey: "appl_test_key", entitlementID: "premium", offeringID: nil),
            forcedPremiumEnabled: nil,
            isTesting: false,
            purchasesClient: client
        )

        let preparation = Task { await store.prepare() }
        defer { client.resumeCustomerInfo() }
        try await waitUntilPremiumCondition("RevenueCat customer info request did not start") {
            client.customerInfoCallCount == 1
        }

        preparation.cancel()
        client.resumeCustomerInfo()
        await preparation.value

        #expect(store.canAccessAIFeatures == false)
        #expect(store.state == .idle)
        #expect(client.customerInfoStreamCallCount == 0)
    }

    @Test("Customer info stream does not retain the premium store")
    func customerInfoStreamDoesNotRetainStore() async throws {
        let client = FakePurchasesClient()
        client.customerInfoResult = .success(makeCustomerInfo(activeEntitlementIDs: []))
        client.offeringsResult = .failure(CocoaError(.fileReadUnknown))
        let (customerInfoStream, streamContinuation) = AsyncStream<CustomerInfo>.makeStream()
        client.customerInfoStreamOverride = customerInfoStream
        defer { streamContinuation.finish() }

        var store: PremiumAccessStore? = makePremiumAccessStore(client: client)
        let weakStore = WeakReference(store)
        await store?.prepare()
        try await waitUntilPremiumCondition("RevenueCat customer info stream did not start") {
            client.customerInfoStreamCallCount == 1
        }

        store = nil

        try await waitUntilPremiumCondition("Premium store was retained by its customer info task") {
            weakStore.value == nil
        }
        #expect(weakStore.value == nil)
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

    @Test("restore does not unlock premium for an unrelated single active entitlement")
    func restoreDoesNotUnlockPremiumForUnrelatedSingleActiveEntitlement() async {
        let client = FakePurchasesClient()
        client.restoreResult = .success(
            makeCustomerInfo(activeEntitlementIDs: ["supporter"])
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

    @Test("restore does not unlock premium from product ids without a matching entitlement")
    func restoreDoesNotUnlockPremiumFromProductIDsWithoutMatchingEntitlement() async {
        let client = FakePurchasesClient()
        client.restoreResult = .success(
            makeCustomerInfo(
                activeEntitlementIDs: [],
                activeProductIDs: [
                    "monthly",
                    "com.mneves.aipedometer.premium.yearly"
                ],
                purchasedProductIDs: [
                    "monthly",
                    "com.mneves.aipedometer.premium.yearly"
                ]
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

    @Test("restore does not unlock premium for an expired known premium product")
    func restoreDoesNotUnlockPremiumForExpiredKnownPremiumProduct() async {
        let client = FakePurchasesClient()
        client.restoreResult = .success(
            makeCustomerInfo(
                activeEntitlementIDs: [],
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
        #expect(store.canAccessAIFeatures == false)
    }

    @Test("restore does not unlock premium when RevenueCat entitlement verification fails")
    func restoreDoesNotUnlockPremiumWhenEntitlementVerificationFails() async {
        let client = FakePurchasesClient()
        client.restoreResult = .success(
            makeCustomerInfo(activeEntitlementIDs: ["premium"], verification: .failed)
        )

        let store = PremiumAccessStore(
            configuration: .init(apiKey: "appl_test_key", entitlementID: "premium", offeringID: nil),
            forcedPremiumEnabled: nil,
            isTesting: false,
            purchasesClient: client
        )

        await store.restorePurchases()

        #expect(store.customerInfo == nil)
        if case .unavailable = store.state {
            // Expected.
        } else {
            Issue.record("Expected failed restore verification to make premium unavailable")
        }
        #expect(store.canAccessAIFeatures == false)
    }

    @Test("current environment ignores an active entitlement from another environment")
    func currentEnvironmentIgnoresActiveEntitlementFromAnotherEnvironment() async {
        let client = FakePurchasesClient()
        client.customerInfoResult = .success(
            makeCustomerInfo(activeEntitlementIDs: ["premium"], isSandbox: false)
        )

        let store = PremiumAccessStore(
            configuration: .init(apiKey: "appl_test_key", entitlementID: "premium", offeringID: nil),
            forcedPremiumEnabled: nil,
            isTesting: false,
            purchasesClient: client
        )

        await store.refresh()

        #expect(store.state == .ready)
        #expect(store.canAccessAIFeatures == false)
    }

    @Test("syncPurchases unlocks premium from verified customer info")
    func syncPurchasesUnlocksVerifiedPremium() async {
        let client = FakePurchasesClient()
        client.syncResult = .success(makeCustomerInfo(activeEntitlementIDs: ["premium"]))
        let store = makePremiumAccessStore(client: client)

        await store.syncPurchases()

        #expect(client.syncCallCount == 1)
        #expect(store.state == .ready)
        #expect(store.canAccessAIFeatures == true)
        #expect(store.lastError == nil)
    }

    @Test("syncPurchases fails closed when entitlement verification fails")
    func syncPurchasesFailsClosedForInvalidVerification() async {
        let client = FakePurchasesClient()
        client.syncResult = .success(
            makeCustomerInfo(activeEntitlementIDs: ["premium"], verification: .failed)
        )
        let store = makePremiumAccessStore(client: client)

        await store.syncPurchases()

        #expect(client.syncCallCount == 1)
        #expect(store.customerInfo == nil)
        if case .unavailable = store.state {
            // Expected.
        } else {
            Issue.record("Expected failed sync verification to make premium unavailable")
        }
        #expect(store.canAccessAIFeatures == false)
        #expect(store.lastError != nil)
    }

    @Test("syncPurchases surfaces a client error without unlocking premium")
    func syncPurchasesSurfacesClientError() async {
        let client = FakePurchasesClient()
        let privateMessage = "RevenueCat sync unavailable at api.example.invalid"
        let publicMessage = String(
            localized: "Subscriptions are unavailable right now. Please try again later.",
            comment: "RevenueCat unavailable state when API key is not configured"
        )
        client.syncResult = .failure(PremiumStoreTestError(message: privateMessage))
        let store = makePremiumAccessStore(client: client)

        await store.syncPurchases()

        #expect(client.syncCallCount == 1)
        #expect(store.state == .unavailable(publicMessage))
        #expect(store.canAccessAIFeatures == false)
        #expect(store.lastError == publicMessage)
        #expect(store.lastError?.contains(privateMessage) == false)
    }

    @Test("syncPurchases does not call RevenueCat when configuration is missing")
    func syncPurchasesSkipsUnconfiguredClient() async {
        let client = FakePurchasesClient()
        let store = makePremiumAccessStore(client: client, apiKey: nil)

        await store.syncPurchases()

        #expect(client.syncCallCount == 0)
        #expect(store.state == .idle)
        #expect(store.canAccessAIFeatures == false)
        #expect(store.lastError == nil)
    }

    @Test("purchase unlocks premium after verified success")
    func purchaseUnlocksVerifiedPremium() async {
        let client = FakePurchasesClient()
        client.purchaseResult = .success(
            PremiumPurchaseResult(
                customerInfo: makeCustomerInfo(activeEntitlementIDs: ["premium"]),
                userCancelled: false
            )
        )
        let store = makePremiumAccessStore(client: client)
        let package = makePremiumPackage(identifier: "monthly")

        let didPurchase = await store.purchase(package)

        #expect(didPurchase == true)
        #expect(client.purchaseCallCount == 1)
        #expect(client.purchasedPackageIdentifiers == ["monthly"])
        #expect(store.state == .ready)
        #expect(store.canAccessAIFeatures == true)
        #expect(store.lastError == nil)
    }

    @Test("purchase cancellation does not unlock premium")
    func purchaseCancellationDoesNotUnlockPremium() async {
        let client = FakePurchasesClient()
        client.purchaseResult = .success(
            PremiumPurchaseResult(
                customerInfo: makeCustomerInfo(activeEntitlementIDs: []),
                userCancelled: true
            )
        )
        let store = makePremiumAccessStore(client: client)

        let didPurchase = await store.purchase(makePremiumPackage())

        #expect(didPurchase == false)
        #expect(client.purchaseCallCount == 1)
        #expect(store.state == .ready)
        #expect(store.canAccessAIFeatures == false)
        #expect(store.lastError == nil)
    }

    @Test("an in-flight purchase rejects overlapping package purchases")
    func purchaseIsSingleFlightAcrossPackages() async throws {
        let client = FakePurchasesClient()
        client.purchaseResult = .success(
            PremiumPurchaseResult(
                customerInfo: makeCustomerInfo(activeEntitlementIDs: []),
                userCancelled: false
            )
        )
        client.shouldSuspendFirstPurchase = true
        let store = makePremiumAccessStore(client: client)
        let firstPackage = makePremiumPackage(identifier: "monthly")
        let secondPackage = makePremiumPackage(identifier: "annual")

        let firstPurchase = Task { await store.purchase(firstPackage) }
        defer { client.resumePurchase() }
        try await waitUntilPremiumCondition("First RevenueCat purchase did not start") {
            client.purchaseCallCount == 1
        }

        let overlappingPurchase = await store.purchase(secondPackage)

        #expect(overlappingPurchase == false)
        #expect(client.purchaseCallCount == 1)
        #expect(client.purchasedPackageIdentifiers == ["monthly"])

        client.resumePurchase()
        #expect(await firstPurchase.value == true)
    }

    @Test("refresh does not release a purchase owned by the current store")
    func refreshPreservesLivePurchaseSingleFlight() async throws {
        let client = FakePurchasesClient()
        client.purchaseResult = .success(
            PremiumPurchaseResult(
                customerInfo: makeCustomerInfo(activeEntitlementIDs: []),
                userCancelled: true
            )
        )
        client.shouldSuspendFirstPurchase = true
        let store = makePremiumAccessStore(client: client)
        let firstPurchase = Task { await store.purchase(makePremiumPackage(identifier: "monthly")) }
        defer { client.resumePurchase() }

        try await waitUntilPremiumCondition("First RevenueCat purchase did not start") {
            client.purchaseCallCount == 1
        }

        let productID = makePremiumPackage().storeProduct.productIdentifier
        client.customerInfoResult = .success(
            makeCustomerInfo(
                activeEntitlementIDs: [],
                activeProductIDs: [productID],
                purchaseDate: .now.addingTimeInterval(60),
                expirationDate: .now.addingTimeInterval(86_460)
            )
        )
        await store.refresh()
        let overlappingPurchase = await store.purchase(makePremiumPackage(identifier: "annual"))

        #expect(store.isPurchaseInProgress)
        #expect(overlappingPurchase == false)
        #expect(client.purchaseCallCount == 1)

        client.resumePurchase()
        #expect(await firstPurchase.value == false)
    }

    @Test("purchase fails closed and reports failed entitlement verification")
    func purchaseFailsClosedForInvalidVerification() async {
        let client = FakePurchasesClient()
        client.purchaseResult = .success(
            PremiumPurchaseResult(
                customerInfo: makeCustomerInfo(
                    activeEntitlementIDs: ["premium"],
                    verification: .failed
                ),
                userCancelled: false
            )
        )
        let store = makePremiumAccessStore(client: client)
        let message = String(
            localized: "Purchase verification failed. Please try again.",
            comment: "Error when RevenueCat entitlement verification fails after purchase"
        )

        let didPurchase = await store.purchase(makePremiumPackage())

        #expect(didPurchase == false)
        #expect(client.purchaseCallCount == 1)
        #expect(store.customerInfo == nil)
        #expect(store.state == .unavailable(message))
        #expect(store.canAccessAIFeatures == false)
        #expect(store.lastError == message)
    }

    @Test("purchase surfaces a client error without unlocking premium")
    func purchaseSurfacesClientError() async {
        let client = FakePurchasesClient()
        let privateMessage = "RevenueCat purchase unavailable at api.example.invalid"
        let publicMessage = String(
            localized: "Subscriptions are unavailable right now. Please try again later.",
            comment: "RevenueCat unavailable state when API key is not configured"
        )
        client.purchaseResult = .failure(PremiumStoreTestError(message: privateMessage))
        let store = makePremiumAccessStore(client: client)

        let didPurchase = await store.purchase(makePremiumPackage())

        #expect(didPurchase == false)
        #expect(client.purchaseCallCount == 1)
        #expect(store.state == .unavailable(publicMessage))
        #expect(store.canAccessAIFeatures == false)
        #expect(store.lastError == publicMessage)
        #expect(store.lastError?.contains(privateMessage) == false)
    }

    @Test("payment-pending RevenueCat error remains blocked across store recreation")
    func paymentPendingErrorPersistsPurchaseBlock() async throws {
        let suiteName = "PremiumAccessStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = FakePurchasesClient()
        let productID = makePremiumPackage().storeProduct.productIdentifier
        let baselinePurchaseDate = Date(timeIntervalSince1970: 10_000)
        let baselineExpirationDate = baselinePurchaseDate.addingTimeInterval(86_400)
        client.customerInfoResult = .success(
            makeCustomerInfo(
                activeEntitlementIDs: ["premium"],
                activeProductIDs: [productID],
                purchaseDate: baselinePurchaseDate,
                expirationDate: baselineExpirationDate
            )
        )
        let store = makePremiumAccessStore(
            client: client,
            pendingPurchaseDefaults: defaults
        )
        await store.refresh()
        client.purchaseResult = .failure(
            NSError(
                domain: ErrorCode.errorDomain,
                code: ErrorCode.paymentPendingError.rawValue
            )
        )
        let didPurchase = await store.purchase(makePremiumPackage())

        #expect(didPurchase == false)
        #expect(store.isPurchaseInProgress)
        #expect(store.state == .ready)

        let recreatedStore = makePremiumAccessStore(
            client: FakePurchasesClient(),
            pendingPurchaseDefaults: defaults
        )
        #expect(recreatedStore.isPurchaseInProgress)

        client.syncResult = .success(
            makeCustomerInfo(
                activeEntitlementIDs: ["premium"],
                activeProductIDs: [productID],
                purchaseDate: baselinePurchaseDate,
                expirationDate: baselineExpirationDate
            )
        )
        await store.syncPurchases()
        #expect(store.isPurchaseInProgress)

        client.syncResult = .success(
            makeCustomerInfo(
                activeEntitlementIDs: ["premium"],
                activeProductIDs: [productID],
                purchaseDate: baselinePurchaseDate.addingTimeInterval(3_600),
                expirationDate: baselineExpirationDate.addingTimeInterval(3_600)
            )
        )
        await store.syncPurchases()
        #expect(store.isPurchaseInProgress == false)

        let resolvedStore = makePremiumAccessStore(
            client: FakePurchasesClient(),
            pendingPurchaseDefaults: defaults
        )
        #expect(resolvedStore.isPurchaseInProgress == false)
    }

    @Test("orphaned pre-await purchase marker is cleared during launch refresh")
    func orphanedPurchaseAttemptIsClearedOnRecreation() async throws {
        let suiteName = "PremiumAccessStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let interruptedClient = FakePurchasesClient()
        interruptedClient.shouldSuspendFirstPurchase = true
        interruptedClient.purchaseResult = .success(
            PremiumPurchaseResult(
                customerInfo: makeCustomerInfo(activeEntitlementIDs: []),
                userCancelled: true
            )
        )
        let interruptedStore = makePremiumAccessStore(
            client: interruptedClient,
            pendingPurchaseDefaults: defaults
        )
        let interruptedPurchase = Task {
            await interruptedStore.purchase(makePremiumPackage())
        }
        defer {
            interruptedClient.resumePurchase()
            interruptedPurchase.cancel()
        }
        try await waitUntilPremiumCondition("Interrupted RevenueCat purchase did not start") {
            interruptedClient.purchaseCallCount == 1
        }

        let recreatedClient = FakePurchasesClient()
        recreatedClient.customerInfoResult = .success(makeCustomerInfo(activeEntitlementIDs: []))
        recreatedClient.syncResult = .success(makeCustomerInfo(activeEntitlementIDs: []))
        recreatedClient.purchaseResult = .success(
            PremiumPurchaseResult(
                customerInfo: makeCustomerInfo(activeEntitlementIDs: []),
                userCancelled: true
            )
        )
        let recreatedStore = makePremiumAccessStore(
            client: recreatedClient,
            pendingPurchaseDefaults: defaults
        )

        await recreatedStore.refresh()

        #expect(recreatedStore.isPurchaseInProgress == false)
        _ = await recreatedStore.purchase(makePremiumPackage())
        #expect(recreatedClient.purchaseCallCount == 1)
    }

    @Test("interrupted attempt survives when StoreKit is finished but RevenueCat sync fails")
    func interruptedAttemptSurvivesFailedRevenueCatSync() async throws {
        let suiteName = "PremiumAccessStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let interruptedClient = FakePurchasesClient()
        interruptedClient.shouldSuspendFirstPurchase = true
        let interruptedStore = makePremiumAccessStore(
            client: interruptedClient,
            pendingPurchaseDefaults: defaults
        )
        let interruptedPurchase = Task {
            await interruptedStore.purchase(makePremiumPackage())
        }
        defer {
            interruptedClient.resumePurchase()
            interruptedPurchase.cancel()
        }
        try await waitUntilPremiumCondition("Interrupted RevenueCat purchase did not start") {
            interruptedClient.purchaseCallCount == 1
        }

        let recreatedClient = FakePurchasesClient()
        recreatedClient.customerInfoResult = .success(makeCustomerInfo(activeEntitlementIDs: []))
        recreatedClient.syncResult = .failure(CocoaError(.fileReadUnknown))
        let recreatedStore = makePremiumAccessStore(
            client: recreatedClient,
            pendingPurchaseDefaults: defaults
        )

        await recreatedStore.refresh()

        #expect(recreatedClient.syncCallCount == 1)
        #expect(recreatedStore.isPurchaseInProgress)
        _ = await recreatedStore.purchase(makePremiumPackage())
        #expect(recreatedClient.purchaseCallCount == 0)
    }

    @Test("launch reconciliation keeps customer info returned by a fresh RevenueCat sync")
    func launchReconciliationKeepsSyncedCustomerInfo() async throws {
        let suiteName = "PremiumAccessStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let productID = "com.mneves.aipedometer.premium.monthly"
        let interruptedClient = FakePurchasesClient()
        interruptedClient.shouldSuspendFirstPurchase = true
        let interruptedStore = makePremiumAccessStore(
            client: interruptedClient,
            pendingPurchaseDefaults: defaults
        )
        let interruptedPurchase = Task {
            await interruptedStore.purchase(makePremiumPackage())
        }
        defer {
            interruptedClient.resumePurchase()
            interruptedPurchase.cancel()
        }
        try await waitUntilPremiumCondition("Interrupted RevenueCat purchase did not start") {
            interruptedClient.purchaseCallCount == 1
        }

        let recreatedClient = FakePurchasesClient()
        recreatedClient.customerInfoResult = .success(makeCustomerInfo(activeEntitlementIDs: []))
        recreatedClient.syncResult = .success(
            makeCustomerInfo(
                activeEntitlementIDs: ["premium"],
                activeProductIDs: [productID],
                purchaseDate: .now.addingTimeInterval(60),
                expirationDate: .now.addingTimeInterval(86_460)
            )
        )
        let recreatedStore = makePremiumAccessStore(
            client: recreatedClient,
            pendingPurchaseDefaults: defaults
        )

        await recreatedStore.refresh()

        #expect(recreatedClient.syncCallCount == 1)
        #expect(recreatedStore.isPremiumActive)
        #expect(recreatedStore.isPurchaseInProgress == false)
    }

    @Test("verified unfinished transaction promotes an interrupted attempt to pending")
    func unfinishedTransactionPromotesInterruptedAttempt() async throws {
        let suiteName = "PremiumAccessStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let productID = "com.mneves.aipedometer.premium.monthly"
        let interruptedClient = FakePurchasesClient()
        interruptedClient.shouldSuspendFirstPurchase = true
        let interruptedStore = makePremiumAccessStore(
            client: interruptedClient,
            pendingPurchaseDefaults: defaults
        )
        let interruptedPurchase = Task {
            await interruptedStore.purchase(makePremiumPackage())
        }
        defer {
            interruptedClient.resumePurchase()
            interruptedPurchase.cancel()
        }
        try await waitUntilPremiumCondition("Interrupted RevenueCat purchase did not start") {
            interruptedClient.purchaseCallCount == 1
        }

        let recreatedClient = FakePurchasesClient()
        recreatedClient.customerInfoResult = .success(makeCustomerInfo(activeEntitlementIDs: []))
        recreatedClient.verifiedUnfinishedProductIDs = [productID]
        let recreatedStore = makePremiumAccessStore(
            client: recreatedClient,
            pendingPurchaseDefaults: defaults
        )

        await recreatedStore.refresh()

        #expect(recreatedStore.isPurchaseInProgress)
        _ = await recreatedStore.purchase(makePremiumPackage())
        #expect(recreatedClient.purchaseCallCount == 0)
    }

    @Test("purchase does not call RevenueCat when configuration is missing")
    func purchaseSkipsUnconfiguredClient() async {
        let client = FakePurchasesClient()
        let store = makePremiumAccessStore(client: client, apiKey: nil)

        let didPurchase = await store.purchase(makePremiumPackage())

        #expect(didPurchase == false)
        #expect(client.purchaseCallCount == 0)
        #expect(client.purchasedPackageIdentifiers.isEmpty)
        #expect(store.state == .idle)
        #expect(store.canAccessAIFeatures == false)
        #expect(store.lastError == nil)
    }
}

private struct PremiumStoreTestError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private final class WeakReference<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

private enum PremiumStoreTestTimeout: LocalizedError {
    case expired(String)

    var errorDescription: String? {
        switch self {
        case .expired(let message):
            return message
        }
    }
}

@MainActor
private func makePremiumAccessStore(
    client: FakePurchasesClient,
    apiKey: String? = "appl_test_key",
    pendingPurchaseDefaults: UserDefaults? = nil
) -> PremiumAccessStore {
    let resolvedDefaults = pendingPurchaseDefaults ?? makeIsolatedPremiumDefaults()
    return PremiumAccessStore(
        configuration: .init(apiKey: apiKey, entitlementID: "premium", offeringID: nil),
        forcedPremiumEnabled: nil,
        isTesting: false,
        purchasesClient: client,
        pendingPurchaseDefaults: resolvedDefaults
    )
}

private func makeIsolatedPremiumDefaults() -> UserDefaults {
    let suiteName = "PremiumAccessStoreTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        preconditionFailure("Unable to create isolated premium test defaults")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private func waitUntilPremiumCondition(
    _ timeoutMessage: String,
    timeout: Duration = .seconds(1),
    condition: @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while !condition() {
        guard clock.now < deadline else {
            throw PremiumStoreTestTimeout.expired(timeoutMessage)
        }
        await Task.yield()
    }
}

private func makePremiumPackage(identifier: String = "monthly") -> Package {
    let product = TestStoreProduct(
        localizedTitle: "Monthly Premium",
        price: 4.99,
        currencyCode: "USD",
        localizedPriceString: "$4.99",
        productIdentifier: "com.mneves.aipedometer.premium.monthly",
        productType: .autoRenewableSubscription,
        localizedDescription: "Premium test product",
        subscriptionGroupIdentifier: "premium",
        subscriptionPeriod: .init(value: 1, unit: .month),
        locale: Locale(identifier: "en_US")
    )

    return Package(
        identifier: identifier,
        packageType: .monthly,
        storeProduct: product.toStoreProduct(),
        offeringIdentifier: "default",
        webCheckoutUrl: nil
    )
}

private func makeCustomerInfo(
    activeEntitlementIDs: Set<String>,
    activeProductIDs: Set<String> = [],
    purchasedProductIDs: Set<String> = [],
    managementURL: URL? = nil,
    isSandbox: Bool = true,
    verification: VerificationResult = .verified,
    purchaseDate: Date = .now,
    expirationDate: Date = .now.addingTimeInterval(86_400)
) -> CustomerInfo {
    let entitlements = activeEntitlementIDs.reduce(into: [String: EntitlementInfo]()) { partialResult, identifier in
        partialResult[identifier] = EntitlementInfo(
            identifier: identifier,
            isActive: true,
            willRenew: true,
            periodType: .normal,
            latestPurchaseDate: purchaseDate,
            originalPurchaseDate: purchaseDate,
            expirationDate: expirationDate,
            store: .appStore,
            productIdentifier: "com.mneves.aipedometer.\(identifier)",
            isSandbox: isSandbox,
            ownershipType: .purchased,
            verification: verification
        )
    }

    let activeProducts = activeProductIDs.union(
        activeEntitlementIDs.map { "com.mneves.aipedometer.\($0)" }
    )
    let purchasedProducts = purchasedProductIDs.union(activeProducts)

    return CustomerInfo(
        entitlements: EntitlementInfos(entitlements: entitlements, verification: verification),
        expirationDatesByProductId: Dictionary(uniqueKeysWithValues: activeProducts.map {
            ($0, expirationDate)
        }),
        purchaseDatesByProductId: Dictionary(uniqueKeysWithValues: purchasedProducts.map {
            ($0, purchaseDate)
        }),
        allPurchasedProductIds: purchasedProducts,
        requestDate: .now,
        firstSeen: .now,
        originalAppUserId: "test-user",
        managementURL: managementURL
    )
}
