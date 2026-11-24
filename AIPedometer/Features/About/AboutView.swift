import StoreKit
import SwiftUI
import UIKit

struct AboutView: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(TipJarStore.self) private var tipJarStore
    private let appVersion: AppVersion
    @State private var tipJarAlert: TipJarAlert?
    
    init(bundle: Bundle = .main) {
        appVersion = AppVersion(info: bundle.infoDictionary ?? [:])
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                heroSection
                supportSection
                featuresSection
                linksSection
                versionSection
            }
            .padding(.horizontal, DesignTokens.Spacing.mdPlus)
            .padding(.bottom, DesignTokens.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .tabBarAwareScrollContentBottomInset()
        .accessibilityIdentifier(A11yID.About.view)
        .background(AmbientZenithBackground())
        .navigationTitle(L10n.localized("About", comment: "Navigation title for About screen"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await tipJarStore.loadProduct()
        }
        .onChange(of: tipJarStore.purchaseState) { _, newValue in
            switch newValue {
            case .success:
                tipJarAlert = .success
            case .pending:
                tipJarAlert = .pending
            case .failed(let message):
                tipJarAlert = .failed(message)
            default:
                break
            }
        }
        .alert(item: $tipJarAlert) { alert in
            switch alert {
            case .success:
                return Alert(
                    title: Text(L10n.localized("Thanks for the coffee!", comment: "Tip jar success alert title")),
                    message: Text(L10n.localized("Your support keeps AI Pedometer improving.", comment: "Tip jar success alert message")),
                    dismissButton: .default(Text(L10n.localized("OK", comment: "Dismiss alert button")))
                )
            case .pending:
                return Alert(
                    title: Text(L10n.localized("Purchase pending", comment: "Tip jar pending alert title")),
                    message: Text(L10n.localized("Your payment is pending approval.", comment: "Tip jar pending alert message")),
                    dismissButton: .default(Text(L10n.localized("OK", comment: "Dismiss alert button")))
                )
            case .failed(let message):
                return Alert(
                    title: Text(L10n.localized("Purchase failed", comment: "Tip jar error alert title")),
                    message: Text(message),
                    dismissButton: .default(Text(L10n.localized("OK", comment: "Dismiss alert button")))
                )
            }
        }
    }
    
    // MARK: - Hero
    
    private var heroSection: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.accent.gradient)
                    .frame(width: 84, height: 84)
                
                Image(systemName: "figure.walk")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.onAccent)
            }
            .shadow(color: DesignTokens.Colors.accent.opacity(0.24), radius: 16, y: 8)
            .accessibilityHidden(true)
            
            VStack(spacing: DesignTokens.Spacing.xxs) {
                Text(L10n.localized("AI Pedometer", comment: "App name"))
                    .font(DesignTokens.Typography.title.bold())
                
                Text(L10n.localized("Your intelligent walking companion", comment: "App tagline"))
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .padding(.top, DesignTokens.Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.localized("AI Pedometer - Your intelligent walking companion", comment: "Accessibility label for app name and tagline"))
    }
    
    // MARK: - Features
    
    private var featuresSection: some View {
        let columns = [
            GridItem(.flexible(), spacing: DesignTokens.Spacing.sm),
            GridItem(.flexible(), spacing: DesignTokens.Spacing.sm)
        ]

        return LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.sm) {
            FeatureTile(
                icon: "brain.head.profile",
                color: DesignTokens.Colors.accent,
                title: L10n.localized("AI-Powered Insights", comment: "Feature title"),
                subtitle: L10n.localized("Personalized coaching powered by Apple Intelligence", comment: "Feature description")
            )
            
            FeatureTile(
                icon: "heart.fill",
                color: DesignTokens.Colors.red,
                title: L10n.localized("HealthKit Integration", comment: "Feature title"),
                subtitle: L10n.localized("Seamlessly syncs with Apple Health", comment: "Feature description")
            )
            
            FeatureTile(
                icon: "lock.shield.fill",
                color: DesignTokens.Colors.green,
                title: L10n.localized("Privacy First", comment: "Feature title"),
                subtitle: L10n.localized("All AI processing happens on-device", comment: "Feature description")
            )
            
            FeatureTile(
                icon: "applewatch",
                color: DesignTokens.Colors.orange,
                title: L10n.localized("Apple Watch", comment: "Feature title"),
                subtitle: L10n.localized("Track your steps from your wrist", comment: "Feature description")
            )
        }
    }
    
    // MARK: - Links
    
    private var linksSection: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            LinkRow(
                icon: "star.fill",
                color: DesignTokens.Colors.yellow,
                title: L10n.localized("Rate on App Store", comment: "Link title"),
                action: openAppStoreReview
            )
            Divider().padding(.leading, 48)
            LinkRow(
                icon: "questionmark.bubble.fill",
                color: DesignTokens.Colors.accent,
                title: L10n.localized("Send Feedback", comment: "Link title"),
                action: openSupport
            )
            Divider().padding(.leading, 48)
            LinkRow(
                icon: "doc.text.fill",
                color: DesignTokens.Colors.neutral,
                title: L10n.localized("Privacy Policy", comment: "Link title"),
                action: openPrivacyPolicy
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .calmCard(cornerRadius: DesignTokens.CornerRadius.xl)
    }

    // MARK: - Support

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.brown)
                    .frame(width: 34, height: 34)
                    .background(DesignTokens.Colors.brown.opacity(0.14), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.localized("Support AI Pedometer", comment: "Support section title in About screen"))
                        .font(DesignTokens.Typography.headline)
                    Text(L10n.localized("One-time tip to support ongoing development.", comment: "Tip jar description in About"))
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }

            if case .failed(let message) = tipJarStore.loadState {
                tipJarUnavailableView(message: message)
            } else {
                supportButton
            }

            Text(L10n.localized("Tips are optional and do not unlock features.", comment: "Tip jar disclaimer"))
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(DesignTokens.Spacing.mdPlus)
        .calmCard(cornerRadius: DesignTokens.CornerRadius.xl)
        .accessibilityElement(children: .contain)
    }

    private func tipJarUnavailableView(message: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(message)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Button(L10n.localized("Try Again", comment: "Retry button")) {
                Task { await tipJarStore.reloadProduct() }
            }
            .glassSecondaryButton()
            .controlSize(.small)
            .accessibilityIdentifier("tipjar_retry_button")
        }
    }

    private var supportButton: some View {
        Button {
            HapticService.shared.tap()
            Task { await tipJarStore.purchase() }
        } label: {
            supportButtonLabel
        }
        .glassButton()
        .accessibilityIdentifier(A11yID.About.tipJarCoffeeButton)
        .disabled(!tipJarStore.canPurchase)
        .accessibleButton(
            label: L10n.localized("Buy me a coffee", comment: "Tip jar button title"),
            hint: tipJarStore.canPurchase
                ? L10n.localized("Supports ongoing development", comment: "Tip jar accessibility hint")
                : L10n.localized("Tip jar is unavailable", comment: "Tip jar unavailable hint")
        )
        .accessibilityValue(tipPriceText)
    }

    private var supportButtonLabel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                if tipJarStore.isPurchasing {
                    ProgressView()
                        .tint(DesignTokens.Colors.onAccent)
                        .controlSize(.small)
                }
                Text(L10n.localized("Buy me a coffee", comment: "Tip jar button title"))
                    .font(DesignTokens.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Spacer()
                Text(tipPriceText)
                    .font(DesignTokens.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.onAccent.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    if tipJarStore.isPurchasing {
                        ProgressView()
                            .tint(DesignTokens.Colors.onAccent)
                            .controlSize(.small)
                    }
                    Text(L10n.localized("Buy me a coffee", comment: "Tip jar button title"))
                        .font(DesignTokens.Typography.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.onAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                Text(tipPriceText)
                    .font(DesignTokens.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.onAccent.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tipPriceText: String {
        switch tipJarStore.loadState {
        case .loaded(let product):
            return product.displayPrice
        case .failed:
            return L10n.localized("Price unavailable", comment: "Tip jar price unavailable")
        case .loading, .idle:
            return L10n.localized("Loading price...", comment: "Tip jar price loading")
        }
    }
    
    // MARK: - Version
    
    private var versionSection: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Text(
                Localization.format(
                    "Version %@ (%@)",
                    comment: "App version label in About screen",
                    appVersion.shortVersion,
                    appVersion.build
                )
            )
                .font(DesignTokens.Typography.footnote.monospaced())
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            
            Text(L10n.localized("Made with care in Brazil", comment: "Footer text"))
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.top, DesignTokens.Spacing.md)
    }
    
    // MARK: - Actions
    
    private func openAppStoreReview() {
        switch AppConstants.reviewAction(appStoreURL: AppConstants.appStoreReviewURL) {
        case .openURL(let url):
            UIApplication.shared.open(url)
        case .requestInApp:
            Loggers.app.warning("appstore.review_unavailable", metadata: [
                "app_store_id": AppConstants.appStoreID
            ])
            HapticService.shared.error()
            requestReview()
        }
    }
    
    private func openSupport() {
        guard let url = AppConstants.Links.support else { return }
        UIApplication.shared.open(url)
    }
    
    private func openPrivacyPolicy() {
        guard let url = AppConstants.Links.privacyPolicy else { return }
        UIApplication.shared.open(url)
    }
}

private enum TipJarAlert: Identifiable {
    case success
    case pending
    case failed(String)

    var id: String {
        switch self {
        case .success:
            return "success"
        case .pending:
            return "pending"
        case .failed(let message):
            return "failed-\(message)"
        }
    }
}

// MARK: - Feature Tile

private struct FeatureTile: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs, style: .continuous))
                .accessibilityHidden(true)

            Text(title)
                .font(DesignTokens.Typography.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(DesignTokens.Spacing.md)
        .calmCard(cornerRadius: DesignTokens.CornerRadius.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

// MARK: - Link Row

private struct LinkRow: View {
    let icon: String
    let color: Color
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticService.shared.tap()
            action()
        }) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs, style: .continuous))
                    .accessibilityHidden(true)
                
                Text(title)
                    .font(DesignTokens.Typography.subheadline.weight(.medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(DesignTokens.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, DesignTokens.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isLink)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
    .environment(TipJarStore())
}
