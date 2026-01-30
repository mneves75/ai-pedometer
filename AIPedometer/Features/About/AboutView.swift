import StoreKit
import SwiftUI
import UIKit

struct AboutView: View {
    private let appVersion: AppVersion
    @Environment(\.requestReview) private var requestReview
    
    init(bundle: Bundle = .main) {
        appVersion = AppVersion(info: bundle.infoDictionary ?? [:])
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xl) {
                heroSection
                featuresSection
                linksSection
                versionSection
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.xxl)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "About", comment: "Navigation title for About screen"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Hero
    
    private var heroSection: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(.blue.gradient)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "figure.walk")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white)
                    .applyIfNotUITesting { view in
                        view.symbolEffect(.pulse.byLayer, options: .repeating.speed(0.3))
                    }
            }
            .shadow(color: .blue.opacity(0.3), radius: 20, y: 10)
            
            VStack(spacing: DesignTokens.Spacing.xs) {
                Text(String(localized: "AI Pedometer", comment: "App name"))
                    .font(.title.bold())
                
                Text(String(localized: "Your intelligent walking companion", comment: "App tagline"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                color: .purple,
                title: String(localized: "AI-Powered Insights", comment: "Feature title"),
                subtitle: String(localized: "Personalized coaching powered by Apple Intelligence", comment: "Feature description")
            )
            
            FeatureRow(
                icon: "heart.fill",
                color: .red,
                title: String(localized: "HealthKit Integration", comment: "Feature title"),
                subtitle: String(localized: "Seamlessly syncs with Apple Health", comment: "Feature description")
            )
            
            FeatureRow(
                icon: "lock.shield.fill",
                color: .green,
                title: String(localized: "Privacy First", comment: "Feature title"),
                subtitle: String(localized: "All AI processing happens on-device", comment: "Feature description")
            )
            
            FeatureRow(
                icon: "applewatch",
                color: .orange,
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
                color: .yellow,
                title: String(localized: "Rate on App Store", comment: "Link title"),
                action: openAppStoreReview
            )
            
            LinkRow(
                icon: "envelope.fill",
                color: .blue,
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
    
    // MARK: - Version
    
    private var versionSection: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Text("v\(appVersion.shortVersion) (\(appVersion.build))")
                .font(.footnote.monospaced())
                .foregroundStyle(.tertiary)
            
            Text(String(localized: "Made with care in Brazil", comment: "Footer text"))
                .font(.caption)
                .foregroundStyle(.secondary)
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

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
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
}
