import RevenueCat
import RevenueCatUI
import SwiftUI

enum PremiumSheetMode: String, Identifiable {
    case paywall

    var id: String { rawValue }
}

enum RevenueCatPaywallPolicy {
    static func packagePurchaseIsDisabled(
        isCurrent: Bool,
        isLoading: Bool,
        isPurchaseInProgress: Bool
    ) -> Bool {
        isCurrent || isLoading || isPurchaseInProgress
    }
}

struct PremiumFeatureGateCard: View {
    @Environment(PremiumAccessStore.self) private var premiumAccessStore

    let title: String
    let message: String
    let accessibilityIdentifier: String?
    @State private var sheetMode: PremiumSheetMode?

    init(title: String, message: String, accessibilityIdentifier: String? = nil) {
        self.title = title
        self.message = message
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "crown.fill")
                    .font(DesignTokens.Typography.title3)
                    .foregroundStyle(DesignTokens.Colors.yellow)
                    .frame(width: DesignTokens.IconSize.md, height: DesignTokens.IconSize.md)
                    .background(DesignTokens.Colors.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(title)
                        .font(DesignTokens.Typography.headline)
                    Text(L10n.localized("Premium", comment: "Premium section title"))
                        .font(DesignTokens.Typography.caption.weight(.medium))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
            }

            Text(message)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                actionButtons
            }

            if !premiumAccessStore.isConfigured {
                Text(
                    PremiumAccessStore.publicUnavailableMessage
                )
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .glassCard()
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
        .sheet(item: $sheetMode) { mode in
            PremiumAccessSheet(mode: mode)
                .environment(premiumAccessStore)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button(L10n.localized("Unlock Premium", comment: "Premium primary button label")) {
            sheetMode = .paywall
        }
        .glassButton()
        .disabled(!premiumAccessStore.isConfigured)

        if premiumAccessStore.isConfigured {
            PremiumRestoreButton()
        }
    }
}

/// Restore Purchases with visible feedback. Restoring with nothing to restore used to look like a
/// button that did nothing, which is also what App Review sees with a fresh sandbox account.
struct PremiumRestoreButton: View {
    @Environment(PremiumAccessStore.self) private var premiumAccessStore
    @State private var isRestoring = false
    @State private var outcome: PremiumAccessStore.RestoreOutcome?

    var body: some View {
        Button {
            Task {
                isRestoring = true
                outcome = await premiumAccessStore.restorePurchases()
                isRestoring = false
            }
        } label: {
            Text(L10n.localized("Restore Purchases", comment: "Restore purchases button"))
        }
        .buttonStyle(.bordered)
        .tint(DesignTokens.Colors.textPrimary)
        .disabled(isRestoring)
        .alert(
            alertTitle,
            isPresented: Binding(get: { outcome != nil }, set: { if !$0 { outcome = nil } })
        ) {
            Button(L10n.localized("OK", comment: "Dismiss alert button")) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var alertTitle: String {
        switch outcome {
        case .restored:
            L10n.localized("Purchases Restored", comment: "Alert title after a successful restore")
        case .nothingToRestore:
            L10n.localized("No Subscription Found", comment: "Alert title when restore finds no active subscription")
        case .failed, nil:
            L10n.localized("Restore Failed", comment: "Alert title when restoring purchases fails")
        }
    }

    private var alertMessage: String {
        switch outcome {
        case .restored:
            L10n.localized("Premium is active.", comment: "Premium active status in About")
        case .nothingToRestore:
            L10n.localized(
                "No active Premium subscription was found for this Apple Account.",
                comment: "Alert message when restore finds no active subscription"
            )
        case .failed, nil:
            PremiumAccessStore.publicUnavailableMessage
        }
    }
}

struct PremiumAccessLoadingCard: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                ProgressView()
                    .controlSize(.small)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(title)
                        .font(DesignTokens.Typography.headline)
                    Text(L10n.localized("Premium", comment: "Premium section title"))
                        .font(DesignTokens.Typography.caption.weight(.medium))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }

            Text(L10n.localized("Loading...", comment: "Premium loading status"))
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(DesignTokens.Spacing.md)
        .glassCard()
    }
}

struct PremiumSubscriptionCard: View {
    @Environment(PremiumAccessStore.self) private var premiumAccessStore
    @State private var sheetMode: PremiumSheetMode?
    @State private var presentCustomerCenter = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "crown.fill")
                    .font(DesignTokens.Typography.title3)
                    .foregroundStyle(DesignTokens.Colors.yellow)
                    .frame(width: DesignTokens.IconSize.md, height: DesignTokens.IconSize.md)
                    .background(DesignTokens.Colors.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(L10n.localized("Premium", comment: "Premium section title"))
                        .font(DesignTokens.Typography.headline)
                    Text(statusText)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                Spacer()
            }

            Text(
                L10n.localized(
                    "Premium unlocks AI insights, AI Coach, training plans, and smart reminders.",
                    comment: "Premium feature summary in About"
                )
            )
            .font(DesignTokens.Typography.subheadline)
            .foregroundStyle(DesignTokens.Colors.textSecondary)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                actionButtons
            }
        }
        .padding(DesignTokens.Spacing.md)
        .glassCard()
        .presentCustomerCenter(
            isPresented: $presentCustomerCenter,
            restoreCompleted: { _ in
                Task { @MainActor in
                    await premiumAccessStore.syncPurchases()
                }
            },
            showingManageSubscriptions: {
                Loggers.app.info("premium.customer_center_manage_subscriptions")
            }
        )
        .sheet(item: $sheetMode) { mode in
            PremiumAccessSheet(mode: mode)
                .environment(premiumAccessStore)
        }
    }

    private var statusText: String {
        if premiumAccessStore.isPremiumActive {
            return L10n.localized("Premium is active.", comment: "Premium active status in About")
        }

        switch premiumAccessStore.state {
        case .loading, .idle:
            return L10n.localized("Loading...", comment: "Premium loading status")
        case .ready:
            return L10n.localized("Unlock Premium", comment: "Premium primary button label")
        case .notConfigured, .unavailable:
            return PremiumAccessStore.publicUnavailableMessage
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button(primaryButtonTitle) {
            if premiumAccessStore.isPremiumActive {
                presentCustomerCenter = true
            } else {
                sheetMode = .paywall
            }
        }
        .glassButton()
        .disabled(!premiumAccessStore.isConfigured)

        if premiumAccessStore.isConfigured {
            PremiumRestoreButton()
        }
    }

    private var primaryButtonTitle: String {
        premiumAccessStore.isPremiumActive
            ? L10n.localized("Manage Subscription", comment: "Manage subscription button")
            : L10n.localized("Unlock Premium", comment: "Premium primary button label")
    }
}

@MainActor
struct PremiumAccessSheet: View {
    let mode: PremiumSheetMode
    @Environment(PremiumAccessStore.self) private var premiumAccessStore
    @Environment(\.dismiss) private var dismiss
    @State private var purchasingPackageID: String?

    var body: some View {
        NavigationStack {
            paywallContent
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.localized("Close", comment: "Dismiss premium sheet")) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await premiumAccessStore.prepare()
        }
    }

    private var paywallContent: some View {
        Group {
            if premiumAccessStore.isConfigured {
                paywallView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                        headerCard
                        unavailableContent

                        if let lastError = premiumAccessStore.lastError, !lastError.isEmpty {
                            Text(lastError)
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.warning)
                                .padding(DesignTokens.Spacing.md)
                                .glassCard()
                        }
                    }
                    .padding(DesignTokens.Spacing.lg)
                }
                .background(DesignTokens.Colors.surfaceGrouped)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "figure.walk.motion")
                    .font(DesignTokens.Typography.title2)
                    .foregroundStyle(DesignTokens.Colors.green)
                    .frame(width: DesignTokens.IconSize.touchTarget, height: DesignTokens.IconSize.touchTarget)
                    .background(DesignTokens.Colors.green.opacity(0.15), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(L10n.localized("Premium", comment: "Premium section title"))
                        .font(DesignTokens.Typography.title3.weight(.semibold))
                    Text(
                        L10n.localized(
                            "Premium unlocks AI insights, AI Coach, training plans, and smart reminders.",
                            comment: "Premium feature summary in About"
                        )
                    )
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                PremiumBulletRow(text: L10n.localized("Daily AI insight grounded in your real step data.", comment: "Premium benefit bullet"))
                PremiumBulletRow(text: L10n.localized("Adaptive training plans with safe fallback logic.", comment: "Premium benefit bullet"))
                PremiumBulletRow(text: L10n.localized("AI Coach and smart reminders behind one entitlement.", comment: "Premium benefit bullet"))
                PremiumBulletRow(text: L10n.localized("GPX route import and Expedition Mode.", comment: "Premium benefit bullet"))
            }

            Text(
                L10n.localized(
                    "AI features run on your device and need an iPhone that supports Apple Intelligence, with Apple Intelligence turned on.",
                    comment: "Premium paywall note on AI device requirements"
                )
            )
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(DesignTokens.Spacing.md)
        .glassCard()
    }

    @ViewBuilder
    private var packageList: some View {
        if premiumAccessStore.availablePackages.isEmpty {
            unavailableContent
        } else {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text(L10n.localized("Choose a plan", comment: "Premium plan section title"))
                    .font(DesignTokens.Typography.headline)

                ForEach(premiumAccessStore.availablePackages, id: \.identifier) { package in
                    PremiumPackageCard(
                        package: package,
                        isCurrent: premiumAccessStore.customerInfo?.activeSubscriptions.contains(package.storeProduct.productIdentifier) == true,
                        isLoading: purchasingPackageID == package.identifier,
                        isPurchaseInProgress: premiumAccessStore.isPurchaseInProgress,
                        purchaseAction: {
                            await purchase(package)
                        }
                    )
                }
            }
        }
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                managementButtons
            }

            Text(
                L10n.localized(
                    "Recurring support keeps AI Pedometer improving, and the coffee tip stays optional.",
                    comment: "Premium recurring support explanation"
                )
            )
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    @ViewBuilder
    private var managementButtons: some View {
        PremiumRestoreButton()

        if premiumAccessStore.isPremiumActive {
            Button(L10n.localized("Manage Subscription", comment: "Manage subscription button")) {
                Task { _ = await premiumAccessStore.showManageSubscriptions() }
            }
            .buttonStyle(.bordered)
            .tint(DesignTokens.Colors.textPrimary)
        }
    }

    @ViewBuilder
    private var paywallView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                headerCard
                packageList
                actionRow
                PremiumSubscriptionTerms()

                // With no packages, `packageList` already renders the unavailable card, and
                // `lastError` carries the same sentence; showing both duplicated the message.
                if !premiumAccessStore.availablePackages.isEmpty,
                   let lastError = premiumAccessStore.lastError, !lastError.isEmpty {
                    Text(lastError)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.warning)
                        .padding(DesignTokens.Spacing.md)
                        .glassCard()
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.surfaceGrouped)
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DesignTokens.Typography.title2)
                .foregroundStyle(DesignTokens.Colors.warning)

            Text(
                PremiumAccessStore.publicUnavailableMessage
            )
            .font(DesignTokens.Typography.subheadline)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .multilineTextAlignment(.leading)

            // `prepare()` runs once per presentation, so a transient StoreKit or network failure
            // used to require closing and reopening the sheet. Without configuration `refresh()`
            // is a no-op, so the button is hidden there.
            if premiumAccessStore.isConfigured {
                Button {
                    Task { await premiumAccessStore.refresh() }
                } label: {
                    Text(L10n.localized("Try Again", comment: "Retry button"))
                }
                .buttonStyle(.bordered)
                .tint(DesignTokens.Colors.textPrimary)
                .disabled(premiumAccessStore.state == .loading)
                .accessibilityIdentifier(A11yID.Premium.retryButton)
            }

            #if DEBUG
            if let storeDiagnostic = premiumAccessStore.storeDiagnostic {
                Text(storeDiagnostic)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textSelection(.enabled)
            }
            #endif
        }
        .padding(DesignTokens.Spacing.md)
        .glassCard()
    }

    private var navigationTitle: String {
        switch mode {
        case .paywall:
            return L10n.localized("Premium", comment: "Premium section title")
        }
    }

    private func purchase(_ package: Package) async {
        purchasingPackageID = package.identifier
        let didPurchase = await premiumAccessStore.purchase(package)
        purchasingPackageID = nil

        if didPurchase && premiumAccessStore.isPremiumActive {
            dismiss()
        }
    }
}

/// Auto-renewal terms and the legal links App Review requires next to a subscription purchase
/// (App Store Review Guideline 3.1.2 and Schedule 2 of the Apple Developer Program License Agreement).
private struct PremiumSubscriptionTerms: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(
                L10n.localized(
                    "Payment is charged to your Apple Account at confirmation. The subscription renews automatically at the price shown for each period unless you cancel at least 24 hours before the period ends. Manage or cancel it in your Apple Account settings.",
                    comment: "Premium paywall auto-renewal disclosure"
                )
            )
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.textSecondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: DesignTokens.Spacing.md) { links }
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) { links }
            }
            .font(DesignTokens.Typography.caption.weight(.medium))
            // Small accent-green text on the grouped background is below AA contrast.
            .underline()
            .tint(DesignTokens.Colors.textPrimary)
        }
    }

    @ViewBuilder
    private var links: some View {
        if let termsOfUse = AppConstants.Links.termsOfUse {
            Link(L10n.localized("Terms of Use (EULA)", comment: "Link to the subscription terms of use"), destination: termsOfUse)
        }
        if let privacyPolicy = AppConstants.Links.privacyPolicy {
            Link(L10n.localized("Privacy Policy", comment: "Link title"), destination: privacyPolicy)
        }
    }
}

private struct PremiumPackageCard: View {
    let package: Package
    let isCurrent: Bool
    let isLoading: Bool
    let isPurchaseInProgress: Bool
    let purchaseAction: @MainActor @Sendable () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(package.storeProduct.localizedTitle)
                        .font(DesignTokens.Typography.headline)
                    Text(packageSubtitle)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                Spacer()

                Text(package.localizedPriceString)
                    .font(DesignTokens.Typography.title3.weight(.semibold))
            }

            Text(package.storeProduct.localizedDescription)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            if let introPrice = package.localizedIntroductoryPriceString {
                Text(
                    Localization.format(
                        "Introductory offer: %@",
                        comment: "Premium introductory offer label",
                        introPrice
                    )
                )
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.success)
            }

            Button(isCurrent ? L10n.localized("Premium is active.", comment: "Premium active status in About") : buttonTitle) {
                Task {
                    await purchaseAction()
                }
            }
            .glassButton()
            .disabled(
                RevenueCatPaywallPolicy.packagePurchaseIsDisabled(
                    isCurrent: isCurrent,
                    isLoading: isLoading,
                    isPurchaseInProgress: isPurchaseInProgress
                )
            )
        }
        .padding(DesignTokens.Spacing.md)
        .glassCard()
    }

    private var packageSubtitle: String {
        guard let period = package.storeProduct.subscriptionPeriod else {
            return packageTypeLabel
        }

        return "\(packageTypeLabel) • \(periodLabel(period))"
    }

    private var buttonTitle: String {
        if isLoading {
            return L10n.localized("Loading...", comment: "Premium loading status")
        }

        return L10n.localized("Unlock Premium", comment: "Premium primary button label")
    }

    private var packageTypeLabel: String {
        switch package.packageType {
        case .monthly:
            return L10n.localized("Monthly", comment: "Monthly package label")
        case .annual:
            return L10n.localized("Annual", comment: "Annual package label")
        case .weekly:
            return L10n.localized("Weekly", comment: "Weekly package label")
        case .lifetime:
            return L10n.localized("Lifetime", comment: "Lifetime package label")
        default:
            return package.identifier
        }
    }

    private func periodLabel(_ period: SubscriptionPeriod) -> String {
        let value = period.value
        let base: String

        switch period.unit {
        case .day:
            base = value == 1
                ? L10n.localized("day", comment: "Subscription period day singular")
                : L10n.localized("days", comment: "Subscription period day plural")
        case .week:
            base = value == 1
                ? L10n.localized("week", comment: "Subscription period week singular")
                : L10n.localized("weeks", comment: "Subscription period week plural")
        case .month:
            base = value == 1
                ? L10n.localized("month", comment: "Subscription period month singular")
                : L10n.localized("months", comment: "Subscription period month plural")
        case .year:
            base = value == 1
                ? L10n.localized("year", comment: "Subscription period year singular")
                : L10n.localized("years", comment: "Subscription period year plural")
        @unknown default:
            base = L10n.localized("period", comment: "Unknown subscription period label")
        }

        return "\(value) \(base)"
    }
}

private struct PremiumBulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DesignTokens.Colors.success)
            Text(text)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }
}
