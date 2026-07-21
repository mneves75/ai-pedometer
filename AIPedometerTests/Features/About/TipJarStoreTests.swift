import Foundation
import Testing

@testable import AIPedometer

actor FakeTipJarDriver: TipJarDriver {
    nonisolated let canMakePayments: Bool

    private var loadResults: [TipJarStore.TipJarProduct?] = []
    private var purchaseResult: Result<TipJarPurchaseOutcome, any Error> = .success(.unknown)
    private var continuation: AsyncStream<TipJarTransactionEvent>.Continuation?
    private(set) var loadCallCount = 0
    private(set) var purchaseCallCount = 0
    private(set) var finishCallCount = 0
    private(set) var finishedTransactionIDs: [String] = []
    private var listenerGeneration = 0
    private var shouldSuspendFinish = false
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var shouldSuspendFirstPurchase = false
    private var purchaseContinuation: CheckedContinuation<Void, Never>?
    private var verifiedUnfinishedProductIDs: Set<String> = []

    init(canMakePayments: Bool) {
        self.canMakePayments = canMakePayments
    }

    func enqueueLoadResults(_ results: [TipJarStore.TipJarProduct?]) {
        loadResults.append(contentsOf: results)
    }

    func setPurchaseResult(_ result: Result<TipJarPurchaseOutcome, any Error>) {
        purchaseResult = result
    }

    func setShouldSuspendFinish(_ shouldSuspend: Bool) {
        shouldSuspendFinish = shouldSuspend
    }

    func setShouldSuspendFirstPurchase(_ shouldSuspend: Bool) {
        shouldSuspendFirstPurchase = shouldSuspend
    }

    func loadProduct() async throws -> TipJarStore.TipJarProduct? {
        loadCallCount += 1
        guard !loadResults.isEmpty else { return nil }
        return loadResults.removeFirst()
    }

    func purchase() async throws -> TipJarPurchaseOutcome {
        purchaseCallCount += 1
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
        shouldSuspendFirstPurchase = false
    }

    func setVerifiedUnfinishedProductIDs(_ productIDs: Set<String>) {
        verifiedUnfinishedProductIDs = productIDs
    }

    func hasVerifiedUnfinishedTransaction(productID: String) async -> Bool {
        verifiedUnfinishedProductIDs.contains(productID)
    }

    func finish(transactionID: String) async {
        finishCallCount += 1
        finishedTransactionIDs.append(transactionID)
        if shouldSuspendFinish {
            await withCheckedContinuation { continuation in
                finishContinuation = continuation
            }
        }
    }

    func resumeFinish() {
        finishContinuation?.resume()
        finishContinuation = nil
        shouldSuspendFinish = false
    }

    func transactionEvents() -> AsyncStream<TipJarTransactionEvent> {
        listenerGeneration += 1
        return AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func yield(_ event: TipJarTransactionEvent) {
        continuation?.yield(event)
    }

    func isTransactionListenerReady() -> Bool {
        continuation != nil
    }

    func transactionListenerGeneration() -> Int {
        listenerGeneration
    }
}

@MainActor
private final class TipJarEventProbe {
    private(set) var handledEvents: [TipJarTransactionEvent] = []

    func record(_ event: TipJarTransactionEvent) {
        handledEvents.append(event)
    }

    func contains(_ event: TipJarTransactionEvent) -> Bool {
        handledEvents.contains(event)
    }
}

@MainActor
struct TipJarStoreTests {
    @Test("loadProduct loads product when available")
    func loadProductLoadsProduct() async {
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.enqueueLoadResults([
            TipJarStore.TipJarProduct(id: AppConstants.TipJar.productID, displayPrice: "R$ 4,99")
        ])
        let store = TipJarStore(
            driver: driver,
            maxRetryAttempts: 1,
            initialRetryDelayNs: 1,
            pendingPurchaseDefaults: makeIsolatedTipJarDefaults()
        )

        await store.loadProduct()

        #expect(store.loadState == .loaded(.init(id: AppConstants.TipJar.productID, displayPrice: "R$ 4,99")))
        #expect(store.canPurchase == true)
        #expect(await driver.loadCallCount == 1)
    }

    @Test("loadProduct fails when payments are restricted")
    func loadProductFailsWhenPaymentsRestricted() async {
        let driver = FakeTipJarDriver(canMakePayments: false)
        let store = TipJarStore(
            driver: driver,
            maxRetryAttempts: 1,
            initialRetryDelayNs: 1,
            pendingPurchaseDefaults: makeIsolatedTipJarDefaults()
        )

        await store.loadProduct()

        guard case .failed(let message) = store.loadState else {
            Issue.record("Expected loadState to be .failed")
            return
        }
        #expect(!message.isEmpty)
        #expect(store.canPurchase == false)
        #expect(await driver.loadCallCount == 0)
    }

    @Test("purchase succeeds after a verified transaction")
    func purchaseSucceeds() async {
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.setPurchaseResult(.success(.success(transactionID: "transaction-1")))
        let store = await makeLoadedTipJarStore(driver: driver)

        await store.purchase()

        #expect(store.purchaseState == .success)
        #expect(store.canPurchase == true)
        #expect(await driver.purchaseCallCount == 1)
        #expect(await driver.finishCallCount == 1)
        #expect(await driver.finishedTransactionIDs == ["transaction-1"])
    }

    @Test("pending purchase blocks duplicate purchase calls")
    func pendingPurchaseBlocksDuplicatePurchase() async {
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.setPurchaseResult(.success(.pending))
        let store = await makeLoadedTipJarStore(driver: driver)

        await store.purchase()
        await store.purchase()

        #expect(store.purchaseState == .pending)
        #expect(store.canPurchase == false)
        #expect(await driver.purchaseCallCount == 1)
    }

    @Test("Foregrounding never releases a pending purchase for a duplicate charge")
    func foregroundingKeepsPendingPurchaseBlocked() async {
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.setPurchaseResult(.success(.pending))
        let store = await makeLoadedTipJarStore(driver: driver)

        await store.purchase()
        store.handleAppBecameActive()

        #expect(store.purchaseState == .pending)
        #expect(store.canPurchase == false)
        await store.purchase()
        #expect(await driver.purchaseCallCount == 1)
    }

    @Test("Pending purchase remains blocked after the store is recreated")
    func pendingPurchasePersistsAcrossStoreRecreation() async throws {
        let suiteName = "TipJarStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.setPurchaseResult(.success(.pending))
        var store: TipJarStore? = await makeLoadedTipJarStore(
            driver: driver,
            pendingPurchaseDefaults: defaults
        )

        await store?.purchase()
        #expect(store?.purchaseState == .pending)
        store = nil

        let recreatedStore = await makeLoadedTipJarStore(
            driver: driver,
            pendingPurchaseDefaults: defaults
        )
        try await waitUntil("Recreated Tip Jar transaction listener did not start") {
            await driver.transactionListenerGeneration() >= 2
        }
        #expect(recreatedStore.purchaseState == .pending)
        #expect(recreatedStore.canPurchase == false)
        await recreatedStore.purchase()
        #expect(await driver.purchaseCallCount == 1)

        await driver.yield(.tipDelivered(transactionID: "approved-tip"))
        try await waitUntil("Approved pending Tip Jar purchase was not delivered") {
            recreatedStore.purchaseState == .success
        }

        let resolvedStore = await makeLoadedTipJarStore(
            driver: driver,
            pendingPurchaseDefaults: defaults
        )
        #expect(resolvedStore.purchaseState == .idle)
        #expect(resolvedStore.canPurchase)
        #expect(await driver.finishCallCount == 1)
    }

    @Test("Orphaned pre-await Tip Jar marker is cleared after recreation")
    func orphanedPurchaseAttemptIsClearedOnRecreation() async throws {
        let suiteName = "TipJarStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.setPurchaseResult(.success(.cancelled))
        await driver.setShouldSuspendFirstPurchase(true)
        let interruptedStore = await makeLoadedTipJarStore(
            driver: driver,
            pendingPurchaseDefaults: defaults
        )
        let interruptedPurchase = Task { await interruptedStore.purchase() }
        defer {
            Task { await driver.resumePurchase() }
            interruptedPurchase.cancel()
        }
        try await waitUntil("Interrupted Tip Jar purchase did not start") {
            await driver.purchaseCallCount == 1
        }

        let recreatedStore = await makeLoadedTipJarStore(
            driver: driver,
            pendingPurchaseDefaults: defaults
        )

        #expect(recreatedStore.purchaseState == .idle)
        #expect(recreatedStore.canPurchase)
    }

    @Test("Verified unfinished Tip Jar transaction promotes an interrupted attempt to pending")
    func unfinishedTransactionPromotesInterruptedAttempt() async throws {
        let suiteName = "TipJarStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let interruptedDriver = FakeTipJarDriver(canMakePayments: true)
        await interruptedDriver.setShouldSuspendFirstPurchase(true)
        let interruptedStore = await makeLoadedTipJarStore(
            driver: interruptedDriver,
            pendingPurchaseDefaults: defaults
        )
        let interruptedPurchase = Task { await interruptedStore.purchase() }
        defer {
            Task { await interruptedDriver.resumePurchase() }
            interruptedPurchase.cancel()
        }
        try await waitUntil("Interrupted Tip Jar purchase did not start") {
            await interruptedDriver.purchaseCallCount == 1
        }

        let recreatedDriver = FakeTipJarDriver(canMakePayments: true)
        await recreatedDriver.setVerifiedUnfinishedProductIDs([AppConstants.TipJar.productID])
        let recreatedStore = await makeLoadedTipJarStore(
            driver: recreatedDriver,
            pendingPurchaseDefaults: defaults
        )

        #expect(recreatedStore.purchaseState == .pending)
        #expect(recreatedStore.canPurchase == false)
        await recreatedStore.purchase()
        #expect(await recreatedDriver.purchaseCallCount == 0)
    }

    @Test("cancelled purchase returns to an available non-success state")
    func purchaseCancellation() async {
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.setPurchaseResult(.success(.cancelled))
        let store = await makeLoadedTipJarStore(driver: driver)

        await store.purchase()

        #expect(store.purchaseState == .cancelled)
        #expect(store.canPurchase == true)
        #expect(await driver.purchaseCallCount == 1)
        #expect(await driver.finishCallCount == 0)
    }

    @Test("purchase reports failed transaction verification")
    func purchaseReportsFailedVerification() async {
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.setPurchaseResult(.success(.failedVerification))
        let store = await makeLoadedTipJarStore(driver: driver)
        let message = String(
            localized: "Purchase verification failed. Please try again.",
            comment: "Error when StoreKit verification fails"
        )

        await store.purchase()

        #expect(store.purchaseState == .failed(message))
        #expect(store.canPurchase == false)
        #expect(await driver.purchaseCallCount == 1)
    }

    @Test("purchase maps an unknown StoreKit result to a generic failure")
    func purchaseReportsUnknownResult() async {
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.setPurchaseResult(.success(.unknown))
        let store = await makeLoadedTipJarStore(driver: driver)
        let message = L10n.localized("Please try again later.", comment: "Generic retry message")

        await store.purchase()

        #expect(store.purchaseState == .failed(message))
        #expect(store.canPurchase == true)
        #expect(await driver.purchaseCallCount == 1)
    }

    @Test("purchase surfaces a typed driver error")
    func purchaseSurfacesTypedDriverError() async {
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.setPurchaseResult(.failure(TipJarDriverError.productUnavailable))
        let store = await makeLoadedTipJarStore(driver: driver)
        let message = String(
            localized: "Product not available. Please try again later.",
            comment: "Error when product is not found"
        )

        await store.purchase()

        #expect(store.purchaseState == .failed(message))
        #expect(store.canPurchase == true)
        #expect(await driver.purchaseCallCount == 1)
    }

    @Test("purchase hides an arbitrary client error behind a generic message")
    func purchaseSurfacesGenericClientError() async {
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.setPurchaseResult(.failure(TipJarStoreTestError(message: "raw client error")))
        let store = await makeLoadedTipJarStore(driver: driver)
        let message = String(
            localized: "Unable to complete purchase. Please try again.",
            comment: "Tip jar purchase failed message"
        )

        await store.purchase()

        #expect(store.purchaseState == .failed(message))
        #expect(store.canPurchase == true)
        #expect(await driver.purchaseCallCount == 1)
    }

    @Test("purchase is a no-op until the product is loaded")
    func purchaseSkipsDriverWithoutLoadedProduct() async {
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.setPurchaseResult(.success(.success(transactionID: "unexpected")))
        let store = TipJarStore(
            driver: driver,
            maxRetryAttempts: 1,
            initialRetryDelayNs: 1,
            pendingPurchaseDefaults: makeIsolatedTipJarDefaults()
        )

        await store.purchase()

        #expect(store.purchaseState == .idle)
        #expect(store.canPurchase == false)
        #expect(await driver.purchaseCallCount == 0)
    }

    @Test("pending purchase becomes success when transaction is delivered")
    func pendingPurchaseBecomesSuccessOnTransactionDelivery() async throws {
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.setPurchaseResult(.success(.pending))
        let probe = TipJarEventProbe()
        let store = await makeLoadedTipJarStore(
            driver: driver,
            onTransactionEventHandled: { probe.record($0) }
        )
        try await waitUntil("Tip Jar transaction listener did not start") {
            await driver.isTransactionListenerReady()
        }

        await store.purchase()
        #expect(store.purchaseState == .pending)

        let event = TipJarTransactionEvent.tipDelivered(transactionID: "123")
        await driver.yield(event)
        try await waitUntil("Tip Jar delivery event was not handled") {
            probe.contains(event)
        }

        #expect(store.purchaseState == .success)
        #expect(store.canPurchase == true)
        #expect(await driver.purchaseCallCount == 1)
        #expect(await driver.finishCallCount == 1)
    }

    @Test("transaction delivery does not surface success when no purchase is in-flight")
    func transactionDeliveryDoesNotSurfaceSuccessWhenIdle() async throws {
        let driver = FakeTipJarDriver(canMakePayments: true)
        let probe = TipJarEventProbe()
        let store = await makeLoadedTipJarStore(
            driver: driver,
            onTransactionEventHandled: { probe.record($0) }
        )
        try await waitUntil("Tip Jar transaction listener did not start") {
            await driver.isTransactionListenerReady()
        }

        #expect(store.purchaseState == .idle)

        let event = TipJarTransactionEvent.tipDelivered(transactionID: "999")
        await driver.yield(event)
        try await waitUntil("Idle Tip Jar delivery event was not handled") {
            probe.contains(event)
        }

        #expect(store.purchaseState == .idle)
        #expect(store.canPurchase == true)
        #expect(await driver.purchaseCallCount == 0)
        #expect(await driver.finishCallCount == 1)
    }

    @Test("verified handoff clears a persisted pending marker before StoreKit finish")
    func verifiedHandoffCannotStrandPendingPurchase() async throws {
        let suiteName = "TipJarStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.setPurchaseResult(.success(.success(transactionID: "verified-tip")))
        await driver.setShouldSuspendFinish(true)
        let store = await makeLoadedTipJarStore(
            driver: driver,
            pendingPurchaseDefaults: defaults
        )

        let purchase = Task { await store.purchase() }
        defer { Task { await driver.resumeFinish() } }
        try await waitUntil("Tip Jar finish did not start") {
            await driver.finishCallCount == 1
        }

        let recreatedStore = await makeLoadedTipJarStore(
            driver: driver,
            pendingPurchaseDefaults: defaults
        )
        #expect(recreatedStore.purchaseState == .idle)
        #expect(recreatedStore.canPurchase)

        await driver.resumeFinish()
        await purchase.value
        #expect(store.purchaseState == .success)
    }

    @Test("failed verification keeps a pending Tip Jar purchase blocked")
    func verificationFailureEventKeepsPendingPurchaseBlocked() async throws {
        let suiteName = "TipJarStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.setPurchaseResult(.success(.pending))
        let probe = TipJarEventProbe()
        let store = await makeLoadedTipJarStore(
            driver: driver,
            pendingPurchaseDefaults: defaults,
            onTransactionEventHandled: { probe.record($0) }
        )
        try await waitUntil("Tip Jar transaction listener did not start") {
            await driver.isTransactionListenerReady()
        }
        await store.purchase()

        let event = TipJarTransactionEvent.verificationFailed(productID: AppConstants.TipJar.productID)
        await driver.yield(event)
        try await waitUntil("Tip Jar verification failure event was not handled") {
            probe.contains(event)
        }

        let message = String(
            localized: "Purchase verification failed. Please try again.",
            comment: "Error when StoreKit verification fails"
        )
        #expect(store.purchaseState == .failed(message))
        #expect(store.canPurchase == false)
        #expect(await driver.purchaseCallCount == 1)

        let recreatedStore = await makeLoadedTipJarStore(
            driver: driver,
            pendingPurchaseDefaults: defaults
        )
        #expect(recreatedStore.purchaseState == .pending)
        #expect(recreatedStore.canPurchase == false)
    }

    @Test("failed verification for another product leaves a pending Tip Jar purchase unchanged")
    func unrelatedVerificationFailureDoesNotFailPendingPurchase() async throws {
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.setPurchaseResult(.success(.pending))
        let probe = TipJarEventProbe()
        let store = await makeLoadedTipJarStore(
            driver: driver,
            onTransactionEventHandled: { probe.record($0) }
        )
        try await waitUntil("Tip Jar transaction listener did not start") {
            await driver.isTransactionListenerReady()
        }
        await store.purchase()

        let event = TipJarTransactionEvent.verificationFailed(productID: "com.example.unrelated")
        await driver.yield(event)
        try await waitUntil("Unrelated verification failure event was not handled") {
            probe.contains(event)
        }

        #expect(store.purchaseState == .pending)
        #expect(store.canPurchase == false)
        #expect(await driver.purchaseCallCount == 1)
    }
}

private struct TipJarStoreTestError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private enum TipJarStoreTestTimeout: LocalizedError {
    case expired(String)

    var errorDescription: String? {
        switch self {
        case .expired(let message):
            return message
        }
    }
}

@MainActor
private func makeLoadedTipJarStore(
    driver: FakeTipJarDriver,
    pendingPurchaseDefaults: UserDefaults? = nil,
    onTransactionEventHandled: @escaping @MainActor @Sendable (TipJarTransactionEvent) -> Void = { _ in }
) async -> TipJarStore {
    let resolvedDefaults: UserDefaults
    if let pendingPurchaseDefaults {
        resolvedDefaults = pendingPurchaseDefaults
    } else {
        resolvedDefaults = makeIsolatedTipJarDefaults()
    }
    await driver.enqueueLoadResults([
        TipJarStore.TipJarProduct(id: AppConstants.TipJar.productID, displayPrice: "R$ 4,99")
    ])
    let store = TipJarStore(
        driver: driver,
        maxRetryAttempts: 1,
        initialRetryDelayNs: 1,
        pendingPurchaseDefaults: resolvedDefaults,
        onTransactionEventHandled: onTransactionEventHandled
    )
    await store.loadProduct()
    return store
}

private func makeIsolatedTipJarDefaults() -> UserDefaults {
    guard let defaults = UserDefaults(suiteName: "TipJarStoreTests.\(UUID().uuidString)") else {
        preconditionFailure("Unable to create isolated Tip Jar test defaults")
    }
    return defaults
}

@MainActor
private func waitUntil(
    _ timeoutMessage: String,
    timeout: Duration = .seconds(1),
    condition: @MainActor () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while !(await condition()) {
        guard clock.now < deadline else {
            throw TipJarStoreTestTimeout.expired(timeoutMessage)
        }
        await Task.yield()
    }
}
