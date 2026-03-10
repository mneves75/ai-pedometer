import RevenueCat
import SwiftUI

enum PremiumSheetMode: String, Identifiable {
    case paywall

    var id: String { rawValue }
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
                    .frame(width: 32, height: 32)
                    .background(DesignTokens.Colors.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(title)
                        .font(DesignTokens.Typography.headline)
                    Text(L10n.localized("Premium", comment: "Premium section title"))
                        .font(DesignTokens.Typography.caption.weight(.medium))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }

            Text(message)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            HStack(spacing: DesignTokens.Spacing.sm) {
                Button(L10n.localized("Unlock Premium", comment: "Premium primary button label")) {
                    sheetMode = .paywall
                }
                .glassButton()
                .disabled(!premiumAccessStore.isConfigured)

                if premiumAccessStore.isConfigured {
                    Button(L10n.localized("Restore Purchases", comment: "Restore purchases button")) {
                        Task { await premiumAccessStore.restorePurchases() }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !premiumAccessStore.isConfigured {
                Text(
                    L10n.localized(
                        "Subscriptions are unavailable right now. Please try again later.",
                        comment: "RevenueCat unavailable state when API key is not configured"
                    )
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
}

struct PremiumSubscriptionCard: View {
    @Environment(PremiumAccessStore.self) private var premiumAccessStore
    @State private var sheetMode: PremiumSheetMode?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "crown.fill")
                    .font(DesignTokens.Typography.title3)
                    .foregroundStyle(DesignTokens.Colors.yellow)
                    .frame(width: 32, height: 32)
                    .background(DesignTokens.Colors.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

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

            HStack(spacing: DesignTokens.Spacing.sm) {
                Button(primaryButtonTitle) {
                    if premiumAccessStore.isPremiumActive {
                        Task { _ = await premiumAccessStore.showManageSubscriptions() }
                    } else {
                        sheetMode = .paywall
                    }
                }
                .glassButton()
                .disabled(!premiumAccessStore.isConfigured)

                if premiumAccessStore.isConfigured {
                    Button(L10n.localized("Restore Purchases", comment: "Restore purchases button")) {
                        Task { await premiumAccessStore.restorePurchases() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .glassCard()
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
            return L10n.localized(
                "Subscriptions are unavailable right now. Please try again later.",
                comment: "RevenueCat unavailable state when API key is not configured"
            )
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
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                headerCard

                if premiumAccessStore.isConfigured {
                    packageList
                    actionRow
                } else {
                    unavailableContent
                }

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

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "figure.walk.motion")
                    .font(DesignTokens.Typography.title2)
                    .foregroundStyle(DesignTokens.Colors.green)
                    .frame(width: 44, height: 44)
                    .background(DesignTokens.Colors.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))

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
            }
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
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button(L10n.localized("Restore Purchases", comment: "Restore purchases button")) {
                    Task { await premiumAccessStore.restorePurchases() }
                }
                .buttonStyle(.bordered)

                if premiumAccessStore.isPremiumActive {
                    Button(L10n.localized("Manage Subscription", comment: "Manage subscription button")) {
                        Task { _ = await premiumAccessStore.showManageSubscriptions() }
                    }
                    .buttonStyle(.bordered)
                }
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

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DesignTokens.Typography.title2)
                .foregroundStyle(DesignTokens.Colors.warning)

            Text(
                L10n.localized(
                    "Subscriptions are unavailable right now. Please try again later.",
                    comment: "RevenueCat unavailable state when API key is not configured"
                )
            )
            .font(DesignTokens.Typography.subheadline)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .multilineTextAlignment(.leading)
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

private struct PremiumPackageCard: View {
    let package: Package
    let isCurrent: Bool
    let isLoading: Bool
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
                    String(
                        localized: "Oferta introdutória: \(introPrice)",
                        comment: "Premium introductory offer label"
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
            .disabled(isCurrent || isLoading)
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
            return String(localized: "Mensal", comment: "Monthly package label")
        case .annual:
            return String(localized: "Anual", comment: "Annual package label")
        case .weekly:
            return String(localized: "Semanal", comment: "Weekly package label")
        case .lifetime:
            return String(localized: "Vitalício", comment: "Lifetime package label")
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
                ? String(localized: "dia", comment: "Subscription period day singular")
                : String(localized: "dias", comment: "Subscription period day plural")
        case .week:
            base = value == 1
                ? String(localized: "semana", comment: "Subscription period week singular")
                : String(localized: "semanas", comment: "Subscription period week plural")
        case .month:
            base = value == 1
                ? String(localized: "mês", comment: "Subscription period month singular")
                : String(localized: "meses", comment: "Subscription period month plural")
        case .year:
            base = value == 1
                ? String(localized: "ano", comment: "Subscription period year singular")
                : String(localized: "anos", comment: "Subscription period year plural")
        @unknown default:
            base = String(localized: "período", comment: "Unknown subscription period label")
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
