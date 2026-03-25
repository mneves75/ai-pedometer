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

    let configuration: AppConstants.RevenueCatConfiguration

    private let forcedPremiumEnabled: Bool?
    private let isTesting: Bool
    private let purchasesClient: any PurchasesClientProtocol
    private var customerInfoTask: Task<Void, Never>?

    init(
        configuration: AppConstants.RevenueCatConfiguration = AppConstants.RevenueCat.resolveConfiguration(),
        forcedPremiumEnabled: Bool? = LaunchConfiguration.forcedPremiumEnabled(),
        isTesting: Bool = LaunchConfiguration.isTesting(),
        purchasesClient: any PurchasesClientProtocol = RevenueCatPurchasesClient()
    ) {
        self.configuration = configuration
        self.forcedPremiumEnabled = forcedPremiumEnabled
        self.isTesting = isTesting
        self.purchasesClient = purchasesClient
    }

    deinit {
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

        if isTesting {
            return true
        }

        return resolvedActiveEntitlement?.isActive == true || hasKnownPremiumPurchase
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
        if forcedPremiumEnabled != nil || isTesting {
            state = .ready
            return
        }

        guard isConfigured else {
            state = .notConfigured
            lastError = L10n.localized(
                "Subscriptions are unavailable right now. Please try again later.",
                comment: "RevenueCat unavailable state when API key is not configured"
            )
            return
        }

        configurePurchasesIfNeeded()
        await refresh()
        startCustomerInfoStreamIfNeeded()
    }

    func refresh() async {
        guard isConfigured else { return }
        state = .loading
        var errorMessages: [String] = []

        do {
            customerInfo = try await purchasesClient.customerInfo()
        } catch {
            errorMessages.append(error.localizedDescription)
            Loggers.app.error("premium.customer_info_failed", metadata: ["error": error.localizedDescription])
        }

        do {
            offerings = try await purchasesClient.offerings()
        } catch {
            errorMessages.append(error.localizedDescription)
            Loggers.app.error("premium.offerings_failed", metadata: ["error": error.localizedDescription])
        }

        lastError = errorMessages.first
        if customerInfo != nil {
            state = .ready
        } else if let firstError = errorMessages.first {
            state = .unavailable(firstError)
        } else {
            state = .ready
        }
    }

    func restorePurchases() async {
        guard isConfigured else { return }

        do {
            customerInfo = try await purchasesClient.restorePurchases()
            state = .ready
            lastError = nil
        } catch {
            state = .unavailable(error.localizedDescription)
            lastError = error.localizedDescription
            Loggers.app.error("premium.restore_failed", metadata: ["error": error.localizedDescription])
        }
    }

    func syncPurchases() async {
        guard isConfigured else { return }

        do {
            customerInfo = try await purchasesClient.syncPurchases()
            state = .ready
            lastError = nil
        } catch {
            state = .unavailable(error.localizedDescription)
            lastError = error.localizedDescription
            Loggers.app.error("premium.sync_failed", metadata: ["error": error.localizedDescription])
        }
    }

    func purchase(_ package: Package) async -> Bool {
        guard isConfigured else { return false }

        do {
            let result = try await purchasesClient.purchase(package: package)
            customerInfo = result.customerInfo
            state = .ready
            lastError = nil
            return !result.userCancelled
        } catch {
            state = .unavailable(error.localizedDescription)
            lastError = error.localizedDescription
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

            lastError = error.localizedDescription
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

    private func startCustomerInfoStreamIfNeeded() {
        guard customerInfoTask == nil else { return }
        guard isConfigured else { return }

        customerInfoTask = Task { [weak self] in
            guard let self else { return }
            for await customerInfo in purchasesClient.customerInfoStream() {
                self.customerInfo = customerInfo
                self.state = .ready
            }
        }
    }

    private var resolvedActiveEntitlement: EntitlementInfo? {
        guard let customerInfo else { return nil }

        if let entitlement = customerInfo.entitlements.activeInCurrentEnvironment[configuration.entitlementID] {
            return entitlement
        }

        if let entitlement = customerInfo.entitlements.active[configuration.entitlementID] {
            return entitlement
        }

        let normalizedConfiguredID = Self.normalizeEntitlementID(configuration.entitlementID)
        if let aliasMatch = customerInfo.entitlements.activeInCurrentEnvironment.first(where: {
            Self.normalizeEntitlementID($0.key) == normalizedConfiguredID
        })?.value {
            return aliasMatch
        }

        if let aliasMatch = customerInfo.entitlements.active.first(where: {
            Self.normalizeEntitlementID($0.key) == normalizedConfiguredID
        })?.value {
            return aliasMatch
        }

        let activeCurrent = customerInfo.entitlements.activeInCurrentEnvironment
        if activeCurrent.count == 1 {
            return activeCurrent.first?.value
        }

        let activeAny = customerInfo.entitlements.active
        if activeAny.count == 1 {
            return activeAny.first?.value
        }

        return nil
    }

    private var hasKnownPremiumPurchase: Bool {
        guard let customerInfo else { return false }

        let configuredOfferingProductIDs = Set(availablePackages.map(\.storeProduct.productIdentifier))
        let purchasedProductIDs = customerInfo.activeSubscriptions.union(customerInfo.allPurchasedProductIdentifiers)

        return purchasedProductIDs.contains { productID in
            configuredOfferingProductIDs.contains(productID) || Self.isKnownPremiumProductID(productID)
        }
    }

    private static func isKnownPremiumProductID(_ rawValue: String) -> Bool {
        let normalized = normalizeEntitlementID(rawValue)

        return normalized.hasSuffix("premiummonthly")
            || normalized.hasSuffix("premiumyearly")
            || normalized.hasSuffix("premiumlifetime")
            || normalized == "monthly"
            || normalized == "yearly"
            || normalized == "lifetime"
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
