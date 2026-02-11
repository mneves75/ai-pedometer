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
            VStack(spacing: DesignTokens.Spacing.xl) {
                heroSection
                supportSection
                featuresSection
                linksSection
                versionSection
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.xxl)
        }
        .accessibilityIdentifier(A11yID.About.view)
        .background(DesignTokens.Colors.surfaceGrouped)
        .navigationTitle(String(localized: "About", comment: "Navigation title for About screen"))
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
                    title: Text(String(localized: "Thanks for the coffee!", comment: "Tip jar success alert title")),
                    message: Text(String(localized: "Your support keeps AI Pedometer improving.", comment: "Tip jar success alert message")),
                    dismissButton: .default(Text(String(localized: "OK", comment: "Dismiss alert button")))
                )
            case .pending:
                return Alert(
                    title: Text(String(localized: "Purchase pending", comment: "Tip jar pending alert title")),
                    message: Text(String(localized: "Your payment is pending approval.", comment: "Tip jar pending alert message")),
                    dismissButton: .default(Text(String(localized: "OK", comment: "Dismiss alert button")))
                )
            case .failed(let message):
                return Alert(
                    title: Text(String(localized: "Purchase failed", comment: "Tip jar error alert title")),
                    message: Text(message),
                    dismissButton: .default(Text(String(localized: "OK", comment: "Dismiss alert button")))
                )
            }
        }
    }
    
    // MARK: - Hero
    
    private var heroSection: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.accent.gradient)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "figure.walk")
                    .font(.system(size: DesignTokens.FontSize.sm, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.inverseText)
                    .applyIfNotUITesting { view in
                        view.symbolEffect(.pulse.byLayer, options: .repeating.speed(0.3))
                    }
            }
            .shadow(color: DesignTokens.Colors.accent.opacity(0.3), radius: 20, y: 10)
            
            VStack(spacing: DesignTokens.Spacing.xs) {
                Text(String(localized: "AI Pedometer", comment: "App name"))
                    .font(DesignTokens.Typography.title.bold())
                
                Text(String(localized: "Your intelligent walking companion", comment: "App tagline"))
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .padding(.top, DesignTokens.Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "AI Pedometer - Your intelligent walking companion", comment: "Accessibility label for app name and tagline"))
    }
    
    // MARK: - Features
    
    private var featuresSection: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            FeatureRow(
                icon: "brain.head.profile",
                color: DesignTokens.Colors.accent,
                title: String(localized: "AI-Powered Insights", comment: "Feature title"),
                subtitle: String(localized: "Personalized coaching powered by Apple Intelligence", comment: "Feature description")
            )
            
            FeatureRow(
                icon: "heart.fill",
                color: DesignTokens.Colors.red,
                title: String(localized: "HealthKit Integration", comment: "Feature title"),
                subtitle: String(localized: "Seamlessly syncs with Apple Health", comment: "Feature description")
            )
            
            FeatureRow(
                icon: "lock.shield.fill",
                color: DesignTokens.Colors.green,
                title: String(localized: "Privacy First", comment: "Feature title"),
                subtitle: String(localized: "All AI processing happens on-device", comment: "Feature description")
            )
            
            FeatureRow(
                icon: "applewatch",
                color: DesignTokens.Colors.orange,
                title: String(localized: "Apple Watch", comment: "Feature title"),
                subtitle: String(localized: "Track your steps from your wrist", comment: "Feature description")
            )
        }
        .padding(DesignTokens.Spacing.md)
        .glassCard()
    }
    
    // MARK: - Links
    
    private var linksSection: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            LinkRow(
                icon: "star.fill",
                color: DesignTokens.Colors.yellow,
                title: String(localized: "Rate on App Store", comment: "Link title"),
                action: openAppStoreReview
            )
            
            LinkRow(
                icon: "envelope.fill",
                color: DesignTokens.Colors.accent,
                title: String(localized: "Send Feedback", comment: "Link title"),
                action: openFeedbackEmail
            )
            
            LinkRow(
                icon: "doc.text.fill",
                color: .gray,
                title: String(localized: "Privacy Policy", comment: "Link title"),
                action: openPrivacyPolicy
            )
        }
        .padding(DesignTokens.Spacing.md)
        .glassCard()
    }

    // MARK: - Support

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(DesignTokens.Typography.title3)
                    .foregroundStyle(.brown)
                    .frame(width: 32, height: 32)
                    .background(.brown.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

                Text(String(localized: "Support AI Pedometer", comment: "Support section title in About screen"))
                    .font(DesignTokens.Typography.headline)
            }

            Text(String(localized: "One-time tip to support ongoing development.", comment: "Tip jar description in About"))
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text(String(localized: "Tips are optional and do not unlock features.", comment: "Tip jar disclaimer"))
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            if case .failed(let message) = tipJarStore.loadState {
                tipJarUnavailableView(message: message)
            } else {
                supportButton
            }
        }
        .padding(DesignTokens.Spacing.md)
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private func tipJarUnavailableView(message: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(message)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Button(String(localized: "Try Again", comment: "Retry button")) {
                Task { await tipJarStore.reloadProduct() }
            }
            .buttonStyle(.bordered)
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
            label: String(localized: "Buy me a coffee", comment: "Tip jar button title"),
            hint: tipJarStore.canPurchase
                ? String(localized: "Supports ongoing development", comment: "Tip jar accessibility hint")
                : String(localized: "Tip jar is unavailable", comment: "Tip jar unavailable hint")
        )
    }

    private var supportButtonLabel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                if tipJarStore.isPurchasing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(String(localized: "Buy me a coffee", comment: "Tip jar button title"))
                    .font(DesignTokens.Typography.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Spacer()
                Text(tipPriceText)
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    if tipJarStore.isPurchasing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(String(localized: "Buy me a coffee", comment: "Tip jar button title"))
                        .font(DesignTokens.Typography.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                Text(tipPriceText)
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
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
            return String(localized: "Price unavailable", comment: "Tip jar price unavailable")
        case .loading, .idle:
            return String(localized: "Loading price...", comment: "Tip jar price loading")
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
            
            Text(String(localized: "Made with care in Brazil", comment: "Footer text"))
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
    
    private func openFeedbackEmail() {
        guard let url = URL(string: "mailto:feedback@aipedometer.app?subject=AI%20Pedometer%20Feedback") else { return }
        UIApplication.shared.open(url)
    }
    
    private func openPrivacyPolicy() {
        guard let url = URL(string: "https://aipedometer.app/privacy") else { return }
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

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.title3)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(title)
                    .font(DesignTokens.Typography.subheadline.weight(.medium))
                
                Text(subtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            
            Spacer()
        }
        .accessibilityElement(children: .combine)
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
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.title3)
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                
                Text(title)
                    .font(DesignTokens.Typography.subheadline.weight(.medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(DesignTokens.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
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
