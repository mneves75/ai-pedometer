import RevenueCat
import Testing

@testable import AIPedometer

@MainActor
struct PremiumPaywallPolicyTests {
    @Test("missing offering uses app-owned fallback instead of RevenueCat default paywall")
    func missingOfferingUsesFallback() {
        #expect(RevenueCatPaywallPolicy.shouldUseOfficialPaywall(for: nil) == false)
    }

    @Test("offering without RevenueCat Paywall v2 uses app-owned package UI")
    func offeringWithoutConfiguredPaywallUsesFallback() {
        let offering = Offering(
            identifier: "default",
            serverDescription: "Default offering",
            availablePackages: [],
            webCheckoutUrl: nil
        )

        #expect(RevenueCatPaywallPolicy.shouldUseOfficialPaywall(for: offering) == false)
    }
}
