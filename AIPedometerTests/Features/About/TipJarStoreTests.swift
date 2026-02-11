import Foundation
import Testing

@testable import AIPedometer

actor FakeTipJarDriver: TipJarDriver {
    nonisolated let canMakePayments: Bool

    private var loadResults: [TipJarStore.TipJarProduct?] = []
    private var purchaseResult: Result<TipJarPurchaseOutcome, any Error> = .success(.unknown)
    private var continuation: AsyncStream<TipJarTransactionEvent>.Continuation?

    init(canMakePayments: Bool) {
        self.canMakePayments = canMakePayments
    }

    func enqueueLoadResults(_ results: [TipJarStore.TipJarProduct?]) {
        loadResults.append(contentsOf: results)
    }

    func setPurchaseResult(_ result: Result<TipJarPurchaseOutcome, any Error>) {
        purchaseResult = result
    }

    func loadProduct() async throws -> TipJarStore.TipJarProduct? {
        guard !loadResults.isEmpty else { return nil }
        return loadResults.removeFirst()
    }

    func purchase() async throws -> TipJarPurchaseOutcome {
        try purchaseResult.get()
    }

    func transactionEvents() -> AsyncStream<TipJarTransactionEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func yield(_ event: TipJarTransactionEvent) {
        continuation?.yield(event)
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
        let store = TipJarStore(driver: driver, maxRetryAttempts: 1, initialRetryDelayNs: 1)

        await store.loadProduct()

        #expect(store.loadState == .loaded(.init(id: AppConstants.TipJar.productID, displayPrice: "R$ 4,99")))
    }

    @Test("loadProduct fails when payments are restricted")
    func loadProductFailsWhenPaymentsRestricted() async {
        let driver = FakeTipJarDriver(canMakePayments: false)
        let store = TipJarStore(driver: driver, maxRetryAttempts: 1, initialRetryDelayNs: 1)

        await store.loadProduct()

        guard case .failed(let message) = store.loadState else {
            Issue.record("Expected loadState to be .failed")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test("pending purchase becomes success when transaction is delivered")
    func pendingPurchaseBecomesSuccessOnTransactionDelivery() async throws {
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.enqueueLoadResults([
            TipJarStore.TipJarProduct(id: AppConstants.TipJar.productID, displayPrice: "R$ 4,99")
        ])
        await driver.setPurchaseResult(.success(.pending))

        let store = TipJarStore(driver: driver, maxRetryAttempts: 1, initialRetryDelayNs: 1)
        await store.loadProduct()

        await store.purchase()
        #expect(store.purchaseState == .pending)

        await driver.yield(.tipDelivered(transactionID: "123"))
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(store.purchaseState == .success)
    }

    @Test("transaction delivery does not surface success when no purchase is in-flight")
    func transactionDeliveryDoesNotSurfaceSuccessWhenIdle() async throws {
        let driver = FakeTipJarDriver(canMakePayments: true)
        await driver.enqueueLoadResults([
            TipJarStore.TipJarProduct(id: AppConstants.TipJar.productID, displayPrice: "R$ 4,99")
        ])
        let store = TipJarStore(driver: driver, maxRetryAttempts: 1, initialRetryDelayNs: 1)
        await store.loadProduct()

        #expect(store.purchaseState == .idle)

        await driver.yield(.tipDelivered(transactionID: "999"))
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(store.purchaseState == .idle)
    }
}
