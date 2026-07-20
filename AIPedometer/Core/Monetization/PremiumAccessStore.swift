import Foundation
import Observation
import RevenueCat
import UIKit

struct PremiumPurchaseResult: Sendable {
    let customerInfo: CustomerInfo
    let userCancelled: Bool
}

@MainActor
protocol PurchasesClientProtocol {
    func isConfigured() -> Bool
    func configure(apiKey: String)
    func offerings() async throws -> Offerings
    func customerInfo() async throws -> CustomerInfo
    func restorePurchases() async throws -> CustomerInfo
    func syncPurchases() async throws -> CustomerInfo
    func purchase(package: Package) async throws -> PremiumPurchaseResult
    func showManageSubscriptions() async throws
    func customerInfoStream() -> AsyncStream<CustomerInfo>
}

@MainActor
final class RevenueCatPurchasesClient: PurchasesClientProtocol {
    func isConfigured() -> Bool {
        Purchases.isConfigured
    }

    func configure(apiKey: String) {
        guard !Purchases.isConfigured else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        let config = Configuration.Builder(withAPIKey: apiKey)
            .with(purchasesAreCompletedBy: .revenueCat, storeKitVersion: .storeKit2)
            .with(entitlementVerificationMode: .informational)
            .build()
        Purchases.configure(with: config)
    }

    func offerings() async throws -> Offerings {
        try await Purchases.shared.offerings()
    }

    func customerInfo() async throws -> CustomerInfo {
        try await Purchases.shared.customerInfo()
    }

    func restorePurchases() async throws -> CustomerInfo {
        try await Purchases.shared.restorePurchases()
    }

    func syncPurchases() async throws -> CustomerInfo {
        try await Purchases.shared.syncPurchases()
    }

    func purchase(package: Package) async throws -> PremiumPurchaseResult {
        let result = try await Purchases.shared.purchase(package: package)
        return PremiumPurchaseResult(
            customerInfo: result.customerInfo,
            userCancelled: result.userCancelled
        )
    }

    func showManageSubscriptions() async throws {
        try await Purchases.shared.showManageSubscriptions()
    }

    func customerInfoStream() -> AsyncStream<CustomerInfo> {
        Purchases.shared.customerInfoStream
    }
}

@MainActor
@Observable
final class PremiumAccessStore {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case notConfigured
        case unavailable(String)
    }

    private(set) var state: State = .idle
    private(set) var customerInfo: CustomerInfo?
    private(set) var offerings: Offerings?
    private(set) var lastError: String?
    private(set) var isPurchaseInProgress = false

    let configuration: AppConstants.RevenueCatConfiguration

    private let forcedPremiumEnabled: Bool?
    private let isTesting: Bool
    private let purchasesClient: any PurchasesClientProtocol
    private let pendingPurchaseDefaults: UserDefaults
    private var customerInfoTask: Task<Void, Never>?
    private var hasPendingPurchase: Bool

    private static let pendingProductKey = "PremiumAccessStore.pendingProduct"
    private static let pendingStartedAtKey = "PremiumAccessStore.pendingStartedAt"
    private static let pendingBaselinePurchaseDateKey = "PremiumAccessStore.pendingBaselinePurchaseDate"
    private static let pendingBaselineExpirationDateKey = "PremiumAccessStore.pendingBaselineExpirationDate"

    private static var publicUnavailableMessage: String {
        L10n.localized(
            "Subscriptions are unavailable right now. Please try again later.",
            comment: "RevenueCat unavailable state when API key is not configured"
        )
    }

    private static var purchaseVerificationFailureMessage: String {
        String(
            localized: "Purchase verification failed. Please try again.",
            comment: "Error when RevenueCat entitlement verification fails after purchase"
        )
    }

    init(
        configuration: AppConstants.RevenueCatConfiguration = AppConstants.RevenueCat.resolveConfiguration(),
        forcedPremiumEnabled: Bool? = LaunchConfiguration.forcedPremiumEnabled(),
        isTesting: Bool = LaunchConfiguration.isTesting(),
        purchasesClient: any PurchasesClientProtocol = RevenueCatPurchasesClient(),
        pendingPurchaseDefaults: UserDefaults = .standard
    ) {
        self.configuration = configuration
        self.forcedPremiumEnabled = forcedPremiumEnabled
        self.isTesting = isTesting
        self.purchasesClient = purchasesClient
        self.pendingPurchaseDefaults = pendingPurchaseDefaults
        let hasPendingPurchase = pendingPurchaseDefaults.string(forKey: Self.pendingProductKey) != nil
        self.hasPendingPurchase = hasPendingPurchase
        self.isPurchaseInProgress = hasPendingPurchase
    }

    deinit {
        // We rely on `assumeIsolated` here because this `@MainActor` class is owned by
        // SwiftUI `@State` and its final deallocation runs on main in every supported
        // configuration. Swift 6.2 strict concurrency also requires the closure form to
        // touch main-isolated stored properties from a nonisolated deinit.
        MainActor.assumeIsolated {
            customerInfoTask?.cancel()
        }
    }

    var isConfigured: Bool {
        configuration.isConfigured
    }

    var isResolvingAccess: Bool {
        guard forcedPremiumEnabled == nil else { return false }
        guard !isTesting else { return false }
        guard isConfigured else { return false }
        guard customerInfo == nil else { return false }

        switch state {
        case .idle, .loading:
            return true
        case .ready, .notConfigured, .unavailable:
            return false
        }
    }

    var isPremiumActive: Bool {
        if let forcedPremiumEnabled {
            return forcedPremiumEnabled
        }

        if customerInfo?.entitlements.verification.isVerified != true {
            return false
        }

        return resolvedActiveEntitlement?.isActive == true
    }

    var canAccessAIFeatures: Bool {
        isPremiumActive
    }

    var currentOffering: Offering? {
        if let offeringID = configuration.offeringID, !offeringID.isEmpty {
            return offerings?.offering(identifier: offeringID)
        }
        return offerings?.current
    }

    var availablePackages: [Package] {
        currentOffering?.availablePackages ?? []
    }

    func prepare() async {
        if forcedPremiumEnabled != nil {
            state = .ready
            return
        }

        guard isConfigured else {
            state = .notConfigured
            lastError = Self.publicUnavailableMessage
            return
        }

        configurePurchasesIfNeeded()
        await refresh()
        guard !Task.isCancelled else { return }
        startCustomerInfoStreamIfNeeded()
    }

    func refresh() async {
        guard isConfigured else { return }
        state = .loading
        var encounteredError = false

        do {
            let resolvedCustomerInfo = try await purchasesClient.customerInfo()
            guard !Task.isCancelled else {
                settleRefreshAfterCancellation()
                return
            }
            if !publishCustomerInfo(
                resolvedCustomerInfo,
                failureMessage: Self.publicUnavailableMessage,
                failureEvent: "premium.customer_info_verification_failed"
            ) {
                encounteredError = true
            }
        } catch is CancellationError {
            settleRefreshAfterCancellation()
            return
        } catch {
            encounteredError = true
            Loggers.app.error("premium.customer_info_failed", metadata: ["error": error.localizedDescription])
        }

        guard !Task.isCancelled else {
            settleRefreshAfterCancellation()
            return
        }

        do {
            let resolvedOfferings = try await purchasesClient.offerings()
            guard !Task.isCancelled else {
                settleRefreshAfterCancellation()
                return
            }
            offerings = resolvedOfferings
        } catch is CancellationError {
            settleRefreshAfterCancellation()
            return
        } catch {
            encounteredError = true
            Loggers.app.error("premium.offerings_failed", metadata: ["error": error.localizedDescription])
        }

        lastError = encounteredError ? Self.publicUnavailableMessage : nil
        if customerInfo != nil {
            state = .ready
        } else if encounteredError {
            state = .unavailable(Self.publicUnavailableMessage)
        } else {
            state = .ready
        }
    }

    func restorePurchases() async {
        guard isConfigured else { return }

        do {
            let resolvedCustomerInfo = try await purchasesClient.restorePurchases()
            guard publishCustomerInfo(
                resolvedCustomerInfo,
                failureMessage: Self.publicUnavailableMessage,
                failureEvent: "premium.restore_verification_failed"
            ) else { return }
            state = .ready
            lastError = nil
        } catch {
            state = .unavailable(Self.publicUnavailableMessage)
            lastError = Self.publicUnavailableMessage
            Loggers.app.error("premium.restore_failed", metadata: ["error": error.localizedDescription])
        }
    }

    func syncPurchases() async {
        guard isConfigured else { return }

        do {
            let resolvedCustomerInfo = try await purchasesClient.syncPurchases()
            guard publishCustomerInfo(
                resolvedCustomerInfo,
                failureMessage: Self.publicUnavailableMessage,
                failureEvent: "premium.sync_verification_failed"
            ) else { return }
            state = .ready
            lastError = nil
        } catch {
            state = .unavailable(Self.publicUnavailableMessage)
            lastError = Self.publicUnavailableMessage
            Loggers.app.error("premium.sync_failed", metadata: ["error": error.localizedDescription])
        }
    }

    func purchase(_ package: Package) async -> Bool {
        guard isConfigured, !isPurchaseInProgress else { return false }
        beginPendingPurchase(for: package)

        do {
            let result = try await purchasesClient.purchase(package: package)
            if result.userCancelled {
                clearPendingPurchase()
            }
            guard publishCustomerInfo(
                result.customerInfo,
                failureMessage: Self.purchaseVerificationFailureMessage,
                failureEvent: "premium.purchase_verification_failed"
            ) else { return false }

            clearPendingPurchase()
            state = .ready
            lastError = nil
            return !result.userCancelled
        } catch where Self.isPaymentPending(error) {
            state = .ready
            lastError = nil
            Loggers.app.info("premium.purchase_pending")
            return false
        } catch {
            clearPendingPurchase()
            state = .unavailable(Self.publicUnavailableMessage)
            lastError = Self.publicUnavailableMessage
            Loggers.app.error("premium.purchase_failed", metadata: [
                "package": package.identifier,
                "error": error.localizedDescription
            ])
            return false
        }
    }

    func showManageSubscriptions() async -> Bool {
        guard isConfigured else { return false }

        do {
            try await purchasesClient.showManageSubscriptions()
            lastError = nil
            return true
        } catch {
            if let url = customerInfo?.managementURL {
                await UIApplication.shared.open(url)
                lastError = nil
                return true
            }

            lastError = Self.publicUnavailableMessage
            Loggers.app.error("premium.manage_subscriptions_failed", metadata: [
                "error": error.localizedDescription
            ])
            return false
        }
    }

    private func configurePurchasesIfNeeded() {
        guard !purchasesClient.isConfigured() else { return }
        guard let apiKey = configuration.apiKey else { return }
        purchasesClient.configure(apiKey: apiKey)
    }

    @discardableResult
    private func publishCustomerInfo(
        _ candidate: CustomerInfo,
        failureMessage: String,
        failureEvent: String
    ) -> Bool {
        guard candidate.entitlements.verification.isVerified else {
            customerInfo = nil
            state = .unavailable(failureMessage)
            lastError = failureMessage
            Loggers.app.error(failureEvent)
            return false
        }

        customerInfo = candidate
        if pendingPurchaseWasResolved(by: candidate) {
            clearPendingPurchase()
        }
        return true
    }

    private func beginPendingPurchase(for package: Package) {
        let productID = package.storeProduct.productIdentifier
        pendingPurchaseDefaults.set(productID, forKey: Self.pendingProductKey)
        pendingPurchaseDefaults.set(Date.now, forKey: Self.pendingStartedAtKey)
        persistOptionalDate(
            customerInfo?.purchaseDate(forProductIdentifier: productID),
            forKey: Self.pendingBaselinePurchaseDateKey
        )
        persistOptionalDate(
            customerInfo?.expirationDate(forProductIdentifier: productID),
            forKey: Self.pendingBaselineExpirationDateKey
        )
        hasPendingPurchase = true
        isPurchaseInProgress = true
    }

    private func pendingPurchaseWasResolved(by candidate: CustomerInfo) -> Bool {
        guard let productID = pendingPurchaseDefaults.string(forKey: Self.pendingProductKey) else {
            return false
        }

        let candidatePurchaseDate = candidate.purchaseDate(forProductIdentifier: productID)
        let candidateExpirationDate = candidate.expirationDate(forProductIdentifier: productID)
        let baselinePurchaseDate = pendingPurchaseDefaults.object(
            forKey: Self.pendingBaselinePurchaseDateKey
        ) as? Date
        let baselineExpirationDate = pendingPurchaseDefaults.object(
            forKey: Self.pendingBaselineExpirationDateKey
        ) as? Date

        if let candidatePurchaseDate {
            if let baselinePurchaseDate, candidatePurchaseDate > baselinePurchaseDate {
                return true
            }
            if baselinePurchaseDate == nil,
               let pendingStartedAt = pendingPurchaseDefaults.object(forKey: Self.pendingStartedAtKey) as? Date,
               candidatePurchaseDate > pendingStartedAt {
                return true
            }
        }

        if let candidateExpirationDate,
           let baselineExpirationDate,
           candidateExpirationDate > baselineExpirationDate {
            return true
        }

        return false
    }

    private func clearPendingPurchase() {
        for key in [
            Self.pendingProductKey,
            Self.pendingStartedAtKey,
            Self.pendingBaselinePurchaseDateKey,
            Self.pendingBaselineExpirationDateKey
        ] {
            pendingPurchaseDefaults.removeObject(forKey: key)
        }
        hasPendingPurchase = false
        isPurchaseInProgress = false
    }

    private func persistOptionalDate(_ date: Date?, forKey key: String) {
        if let date {
            pendingPurchaseDefaults.set(date, forKey: key)
        } else {
            pendingPurchaseDefaults.removeObject(forKey: key)
        }
    }

    private static func isPaymentPending(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == ErrorCode.errorDomain
            && nsError.code == ErrorCode.paymentPendingError.rawValue
    }

    private func settleRefreshAfterCancellation() {
        state = customerInfo == nil ? .idle : .ready
    }

    private func startCustomerInfoStreamIfNeeded() {
        guard customerInfoTask == nil else { return }
        guard isConfigured else { return }

        let purchasesClient = purchasesClient
        customerInfoTask = Task { @MainActor [weak self, purchasesClient] in
            for await customerInfo in purchasesClient.customerInfoStream() {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard self.publishCustomerInfo(
                    customerInfo,
                    failureMessage: Self.publicUnavailableMessage,
                    failureEvent: "premium.stream_verification_failed"
                ) else { continue }
                self.state = .ready
                self.lastError = nil
            }
        }
    }

    private var resolvedActiveEntitlement: EntitlementInfo? {
        guard let customerInfo else { return nil }

        if let entitlement = customerInfo.entitlements.activeInCurrentEnvironment[configuration.entitlementID] {
            return entitlement
        }

        let normalizedConfiguredID = Self.normalizeEntitlementID(configuration.entitlementID)
        if let aliasMatch = customerInfo.entitlements.activeInCurrentEnvironment.first(where: {
            Self.normalizeEntitlementID($0.key) == normalizedConfiguredID
        })?.value {
            return aliasMatch
        }

        if let knownAliasMatch = customerInfo.entitlements.activeInCurrentEnvironment.first(where: {
            Self.isKnownPremiumEntitlementID($0.key)
        })?.value {
            return knownAliasMatch
        }

        return nil
    }

    private static func isKnownPremiumEntitlementID(_ rawValue: String) -> Bool {
        let normalized = normalizeEntitlementID(rawValue)

        return normalized == "premium" || normalized == "aipedometerpro"
    }

    private static func normalizeEntitlementID(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
    }
}
