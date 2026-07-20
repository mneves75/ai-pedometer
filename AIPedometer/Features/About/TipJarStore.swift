import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class TipJarStore {
    struct TipJarProduct: Equatable, Sendable {
        let id: String
        let displayPrice: String
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(TipJarProduct)
        case failed(String)
    }

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case success
        case pending
        case cancelled
        case failed(String)
    }

    private(set) var loadState: LoadState = .idle
    private(set) var purchaseState: PurchaseState = .idle

    private let driver: any TipJarDriver
    private var transactionTask: Task<Void, Never>?
    private let maxRetryAttempts: Int
    private let initialRetryDelayNs: UInt64
    private let pendingPurchaseDefaults: UserDefaults
    private let onTransactionEventHandled: @MainActor @Sendable (TipJarTransactionEvent) -> Void
    private var hasPersistedPendingPurchase: Bool

    private static let pendingPurchaseKey = "TipJarStore.pendingPurchase"
    private static let verifiedSettlementKey = "TipJarStore.verifiedSettlement"

    private static var verificationFailureMessage: String {
        String(
            localized: "Purchase verification failed. Please try again.",
            comment: "Error when StoreKit verification fails"
        )
    }

    init(
        driver: any TipJarDriver = StoreKitTipJarDriver(
            productID: AppConstants.TipJar.productID,
            logger: Loggers.app
        ),
        maxRetryAttempts: Int = 3,
        initialRetryDelayNs: UInt64 = 500_000_000, // 0.5s
        pendingPurchaseDefaults: UserDefaults = .standard,
        onTransactionEventHandled: @escaping @MainActor @Sendable (TipJarTransactionEvent) -> Void = { _ in }
    ) {
        self.driver = driver
        self.maxRetryAttempts = maxRetryAttempts
        self.initialRetryDelayNs = initialRetryDelayNs
        self.pendingPurchaseDefaults = pendingPurchaseDefaults
        self.onTransactionEventHandled = onTransactionEventHandled
        if pendingPurchaseDefaults.string(forKey: Self.verifiedSettlementKey) != nil {
            // A verified transaction was handed off before a previous process ended.
            // StoreKit will redeliver it if it was not finished; it is no longer pending.
            pendingPurchaseDefaults.removeObject(forKey: Self.pendingPurchaseKey)
            pendingPurchaseDefaults.removeObject(forKey: Self.verifiedSettlementKey)
        }
        let hasPersistedPendingPurchase = pendingPurchaseDefaults.bool(forKey: Self.pendingPurchaseKey)
        self.hasPersistedPendingPurchase = hasPersistedPendingPurchase
        if hasPersistedPendingPurchase {
            purchaseState = .pending
        }
        startTransactionListener()
    }

    deinit {
        MainActor.assumeIsolated {
            transactionTask?.cancel()
        }
    }

    var product: TipJarProduct? {
        if case .loaded(let product) = loadState {
            return product
        }
        return nil
    }

    var displayPrice: String? {
        product?.displayPrice
    }

    var isPurchasing: Bool {
        if case .purchasing = purchaseState {
            return true
        }
        return false
    }

    private var hasPurchaseInFlight: Bool {
        if hasPersistedPendingPurchase {
            return true
        }
        switch purchaseState {
        case .purchasing, .pending:
            return true
        default:
            return false
        }
    }

    var canPurchase: Bool {
        product != nil && !hasPurchaseInFlight && driver.canMakePayments
    }

    func loadProduct() async {
        if case .loading = loadState {
            return
        }
        if case .loaded = loadState {
            return
        }

        loadState = .loading

        guard driver.canMakePayments else {
            loadState = .failed(
                String(
                    localized: "In-app purchases are not allowed on this device.",
                    comment: "Tip jar message when in-app purchases are restricted"
                )
            )
            Loggers.app.warning("tip_jar.payments_restricted")
            return
        }

        do {
            let product = try await loadProductWithRetry()
            if Task.isCancelled {
                loadState = .idle
                return
            }
            guard let product else {
                let message: String
                #if DEBUG
                message = String(
                    localized: "Product unavailable. Launch from Xcode (⌘R) to activate StoreKit test configuration.",
                    comment: "Debug tip jar message explaining StoreKit configuration activation requirement"
                )
                #else
                message = String(
                    localized: "Product not available. Please try again later.",
                    comment: "Tip jar product unavailable"
                )
                #endif
                loadState = .failed(message)
                Loggers.app.warning("tip_jar.product_unavailable", metadata: [
                    "attempts": "\(maxRetryAttempts)"
                ])
                return
            }
            loadState = .loaded(product)
        } catch is CancellationError {
            loadState = .idle
        } catch {
            let message = String(
                localized: "Unable to load price. Please try again.",
                comment: "Tip jar product load failure message"
            )
            loadState = .failed(message)
            Loggers.app.error("tip_jar.product_load_failed", metadata: ["error": error.localizedDescription])
        }
    }

    func reloadProduct() async {
        loadState = .idle
        await loadProduct()
    }

    func handleAppBecameActive() {
        // StoreKit owns the lifetime of a pending purchase. Only its transaction
        // update may settle this state; foregrounding must not enable a duplicate.
    }

    /// Loads product with exponential backoff retry (0.5s → 1s → 2s).
    /// Returns nil if all attempts return empty products.
    private func loadProductWithRetry() async throws -> TipJarProduct? {
        var delay = initialRetryDelayNs

        for attempt in 1...maxRetryAttempts {
            let product = try await driver.loadProduct()
            if let product {
                if attempt > 1 {
                    Loggers.app.info("tip_jar.loaded_after_retry", metadata: [
                        "attempt": "\(attempt)"
                    ])
                }
                return product
            }

            guard attempt < maxRetryAttempts else { break }

            Loggers.app.info("tip_jar.retry", metadata: [
                "attempt": "\(attempt)",
                "next_delay_ms": "\(delay / 1_000_000)"
            ])

            try await Task.sleep(nanoseconds: delay)
            delay *= 2
        }

        return nil
    }

    func purchase() async {
        guard product != nil else { return }
        guard !hasPurchaseInFlight else { return }

        setPendingPurchase(true)
        purchaseState = .purchasing

        do {
            let result = try await driver.purchase()
            switch result {
            case .success(let transactionID):
                await settleVerifiedTransaction(transactionID, surfaceSuccess: true)
                Loggers.app.info("tip_jar.purchase_success", metadata: [
                    "product_id": AppConstants.TipJar.productID
                ])
            case .pending:
                purchaseState = .pending
                Loggers.app.info("tip_jar.purchase_pending")
            case .cancelled:
                setPendingPurchase(false)
                purchaseState = .cancelled
            case .failedVerification:
                setPendingPurchase(true)
                purchaseState = .failed(Self.verificationFailureMessage)
            case .unknown:
                setPendingPurchase(false)
                purchaseState = .failed(L10n.localized("Please try again later.", comment: "Generic retry message"))
            }
        } catch let error as TipJarDriverError {
            switch error {
            case .failedVerification:
                setPendingPurchase(true)
            case .productUnavailable:
                setPendingPurchase(false)
            }
            purchaseState = .failed(error.localizedDescription)
            Loggers.app.error("tip_jar.purchase_failed", metadata: ["error": error.localizedDescription])
        } catch {
            setPendingPurchase(false)
            let message = String(
                localized: "Unable to complete purchase. Please try again.",
                comment: "Tip jar purchase failed message"
            )
            purchaseState = .failed(message)
            Loggers.app.error("tip_jar.purchase_failed", metadata: ["error": error.localizedDescription])
        }
    }

    private func startTransactionListener() {
        transactionTask?.cancel()
        transactionTask = Task { [weak self] in
            guard let self else { return }
            let events = await self.driver.transactionEvents()
            for await event in events {
                switch event {
                case .tipDelivered(let transactionID):
                    let shouldSurfaceSuccess = self.hasPurchaseInFlight
                    await self.settleVerifiedTransaction(
                        transactionID,
                        surfaceSuccess: shouldSurfaceSuccess
                    )
                    if shouldSurfaceSuccess {
                        Loggers.app.info("tip_jar.purchase_completed_via_update", metadata: [
                            "product_id": AppConstants.TipJar.productID
                        ])
                    }
                case .verificationFailed(let productID):
                    guard productID == AppConstants.TipJar.productID else { break }
                    switch self.purchaseState {
                    case .pending, .purchasing:
                        self.setPendingPurchase(true)
                        self.purchaseState = .failed(Self.verificationFailureMessage)
                    default:
                        break
                    }
                }
                self.onTransactionEventHandled(event)
            }
        }
    }

    private func setPendingPurchase(_ isPending: Bool) {
        hasPersistedPendingPurchase = isPending
        if isPending {
            pendingPurchaseDefaults.set(true, forKey: Self.pendingPurchaseKey)
        } else {
            pendingPurchaseDefaults.removeObject(forKey: Self.pendingPurchaseKey)
        }
    }

    private func settleVerifiedTransaction(
        _ transactionID: String,
        surfaceSuccess: Bool
    ) async {
        // Persist the verified handoff before the irreversible StoreKit finish.
        // If the process ends first, StoreKit redelivers the unfinished transaction.
        pendingPurchaseDefaults.set(transactionID, forKey: Self.verifiedSettlementKey)
        setPendingPurchase(false)
        if surfaceSuccess {
            purchaseState = .success
        }
        await driver.finish(transactionID: transactionID)
        if pendingPurchaseDefaults.string(forKey: Self.verifiedSettlementKey) == transactionID {
            pendingPurchaseDefaults.removeObject(forKey: Self.verifiedSettlementKey)
        }
    }
}

enum TipJarPurchaseOutcome: Sendable, Equatable {
    case success(transactionID: String)
    case pending
    case cancelled
    case failedVerification
    case unknown
}

enum TipJarTransactionEvent: Sendable, Equatable {
    case tipDelivered(transactionID: String)
    case verificationFailed(productID: String)
}

protocol TipJarDriver: Actor {
    nonisolated var canMakePayments: Bool { get }
    func loadProduct() async throws -> TipJarStore.TipJarProduct?
    func purchase() async throws -> TipJarPurchaseOutcome
    func finish(transactionID: String) async
    func transactionEvents() -> AsyncStream<TipJarTransactionEvent>
}

enum TipJarDriverError: LocalizedError {
    case failedVerification
    case productUnavailable

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return String(
                localized: "Purchase verification failed. Please try again.",
                comment: "Error when StoreKit verification fails"
            )
        case .productUnavailable:
            return String(
                localized: "Product not available. Please try again later.",
                comment: "Error when product is not found"
            )
        }
    }
}

actor StoreKitTipJarDriver: TipJarDriver {
    nonisolated let canMakePayments: Bool = AppStore.canMakePayments

    private let productID: String
    private let logger: AppLogger

    private var cachedProduct: Product?
    private var cachedTransactions: [String: Transaction] = [:]
    private var finishedTransactionIDs: Set<Transaction.ID> = []
    private var listenerStarted = false

    init(productID: String, logger: AppLogger) {
        self.productID = productID
        self.logger = logger
    }

    func loadProduct() async throws -> TipJarStore.TipJarProduct? {
        if let cachedProduct {
            return TipJarStore.TipJarProduct(id: cachedProduct.id, displayPrice: cachedProduct.displayPrice)
        }

        let products = try await Product.products(for: [productID])
        guard let product = products.first else { return nil }
        cachedProduct = product
        return TipJarStore.TipJarProduct(id: product.id, displayPrice: product.displayPrice)
    }

    func purchase() async throws -> TipJarPurchaseOutcome {
        let product = try await resolveProductForPurchase()
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            do {
                let transaction = try checkVerified(verification)
                let transactionID = String(transaction.id)
                cachedTransactions[transactionID] = transaction
                return .success(transactionID: transactionID)
            } catch {
                return .failedVerification
            }
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .unknown
        }
    }

    func transactionEvents() -> AsyncStream<TipJarTransactionEvent> {
        AsyncStream { continuation in
            startListenerIfNeeded(continuation: continuation)
        }
    }

    func finish(transactionID: String) async {
        guard let transaction = cachedTransactions[transactionID] else { return }
        await finishIfNeeded(transaction)
        cachedTransactions.removeValue(forKey: transactionID)
    }

    private func startListenerIfNeeded(continuation: AsyncStream<TipJarTransactionEvent>.Continuation) {
        guard !listenerStarted else { return }
        listenerStarted = true

        Task { [weak self] in
            guard let self else { return }
            // Drain unfinished transactions first to avoid leaving tips un-finished.
            for await result in Transaction.unfinished {
                await self.handleTransactionResult(result, continuation: continuation)
            }
            for await result in Transaction.updates {
                await self.handleTransactionResult(result, continuation: continuation)
            }
        }
    }

    private func handleTransactionResult(
        _ result: VerificationResult<Transaction>,
        continuation: AsyncStream<TipJarTransactionEvent>.Continuation
    ) async {
        switch result {
        case .verified(let transaction):
            guard transaction.productID == productID else { return }
            let transactionID = String(transaction.id)
            cachedTransactions[transactionID] = transaction
            continuation.yield(.tipDelivered(transactionID: transactionID))
        case .unverified(let unsafeTransaction, _):
            let unsafeProductID = unsafeTransaction.productID
            guard unsafeProductID == productID else { return }
            logger.error("tip_jar.transaction_verification_failed", metadata: [
                "product_id": unsafeProductID
            ])
            continuation.yield(.verificationFailed(productID: unsafeProductID))
        }
    }

    private func resolveProductForPurchase() async throws -> Product {
        if let cachedProduct { return cachedProduct }
        let products = try await Product.products(for: [productID])
        guard let product = products.first else { throw TipJarDriverError.productUnavailable }
        cachedProduct = product
        return product
    }

    private func finishIfNeeded(_ transaction: Transaction) async {
        guard !finishedTransactionIDs.contains(transaction.id) else { return }
        finishedTransactionIDs.insert(transaction.id)
        await transaction.finish()
        logger.info("tip_jar.transaction_finished", metadata: [
            "product_id": transaction.productID
        ])
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw TipJarDriverError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}
