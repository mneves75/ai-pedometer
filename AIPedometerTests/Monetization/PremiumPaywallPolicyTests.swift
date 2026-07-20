import Testing

@testable import AIPedometer

@MainActor
struct PremiumPaywallPolicyTests {
    @Test("a pending purchase disables every fallback package option")
    func pendingPurchaseDisablesEveryPackageOption() {
        for isCurrent in [false, true] {
            #expect(
                RevenueCatPaywallPolicy.packagePurchaseIsDisabled(
                    isCurrent: isCurrent,
                    isLoading: false,
                    isPurchaseInProgress: true
                )
            )
        }
    }

    @Test("without a purchase flight, fallback packages preserve current and loading disables")
    func idlePackagePreservesCurrentAndLoadingDisables() {
        #expect(
            RevenueCatPaywallPolicy.packagePurchaseIsDisabled(
                isCurrent: false,
                isLoading: false,
                isPurchaseInProgress: false
            ) == false
        )
        #expect(
            RevenueCatPaywallPolicy.packagePurchaseIsDisabled(
                isCurrent: true,
                isLoading: false,
                isPurchaseInProgress: false
            )
        )
        #expect(
            RevenueCatPaywallPolicy.packagePurchaseIsDisabled(
                isCurrent: false,
                isLoading: true,
                isPurchaseInProgress: false
            )
        )
    }
}
