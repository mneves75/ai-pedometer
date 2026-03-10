import Foundation
import Observation
import RevenueCat
import UIKit

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
    private var customerInfoTask: Task<Void, Never>?

    init(
        configuration: AppConstants.RevenueCatConfiguration = AppConstants.RevenueCat.resolveConfiguration(),
        forcedPremiumEnabled: Bool? = LaunchConfiguration.forcedPremiumEnabled(),
        isTesting: Bool = LaunchConfiguration.isTesting()
    ) {
        self.configuration = configuration
        self.forcedPremiumEnabled = forcedPremiumEnabled
        self.isTesting = isTesting
    }

    deinit {
        MainActor.assumeIsolated {
            customerInfoTask?.cancel()
        }
    }

    var isConfigured: Bool {
        configuration.isConfigured
    }

    var isPremiumActive: Bool {
        if let forcedPremiumEnabled {
            return forcedPremiumEnabled
        }

        if isTesting {
            return true
        }

        if let entitlement = customerInfo?.entitlements.activeInCurrentEnvironment[configuration.entitlementID] {
            return entitlement.isActive
        }

        if let entitlement = customerInfo?.entitlements.active[configuration.entitlementID] {
            return entitlement.isActive
        }

        return false
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
        lastError = nil

        do {
            async let fetchedOfferings = Purchases.shared.offerings()
            async let fetchedCustomerInfo = Purchases.shared.customerInfo()
            offerings = try await fetchedOfferings
            customerInfo = try await fetchedCustomerInfo
            state = .ready
        } catch {
            state = .unavailable(error.localizedDescription)
            lastError = error.localizedDescription
            Loggers.app.error("premium.refresh_failed", metadata: ["error": error.localizedDescription])
        }
    }

    func restorePurchases() async {
        guard isConfigured else { return }

        do {
            customerInfo = try await Purchases.shared.restorePurchases()
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
            customerInfo = try await Purchases.shared.syncPurchases()
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
            let result = try await Purchases.shared.purchase(package: package)
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
            try await Purchases.shared.showManageSubscriptions()
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
        guard !Purchases.isConfigured else { return }
        guard let apiKey = configuration.apiKey else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        let config = Configuration.Builder(withAPIKey: apiKey)
            .with(purchasesAreCompletedBy: .revenueCat, storeKitVersion: .storeKit2)
            .build()
        Purchases.configure(with: config)
    }

    private func startCustomerInfoStreamIfNeeded() {
        guard customerInfoTask == nil else { return }
        guard isConfigured else { return }

        customerInfoTask = Task { [weak self] in
            guard let self else { return }
            for await customerInfo in Purchases.shared.customerInfoStream {
                self.customerInfo = customerInfo
                self.state = .ready
            }
        }
    }
}
