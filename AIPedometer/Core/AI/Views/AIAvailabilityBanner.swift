import SwiftUI
import UIKit

/// Subtle, low-noise banner that communicates AI unavailability without hijacking screen focus.
struct AIAvailabilityBanner: View {
    let reason: AIUnavailabilityReason
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.smPlus) {
            Image(systemName: iconName)
                .font(DesignTokens.Typography.callout.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: DesignTokens.IconSize.md, height: DesignTokens.IconSize.md)
                .background(iconColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(reason.userFacingMessage)
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if reason.hasAction {
                    Button(action: openSettings) {
                        Text(reason.actionTitle)
                            .font(DesignTokens.Typography.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.Colors.accent)
                }
            }

            Spacer(minLength: DesignTokens.Spacing.xs)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(DesignTokens.Typography.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(width: DesignTokens.IconSize.touchTarget, height: DesignTokens.IconSize.touchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.localized("Dismiss", comment: "Dismiss banner button"))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.smPlus)
        .calmCard(cornerRadius: DesignTokens.CornerRadius.lg)
    }

    private var iconName: String {
        switch reason {
        case .deviceNotEligible:
            "iphone.slash"
        case .appleIntelligenceNotEnabled:
            "sparkles"
        case .modelNotReady:
            "hourglass"
        case .unknown:
            "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch reason {
        case .deviceNotEligible:
            DesignTokens.Colors.textSecondary
        case .appleIntelligenceNotEnabled, .modelNotReady:
            DesignTokens.Colors.accent
        case .unknown:
            DesignTokens.Colors.warning
        }
    }

    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        // Not the environment's `openURL`: inside AI Coach that action is replaced by the
        // model-link policy, which only admits https links and would discard this URL.
        UIApplication.shared.open(settingsURL)
    }
}

/// Full-screen AI unavailable state with a valid SF Symbol medallion, clear explanation, and optional action.
struct AIUnavailableStateView: View {
    let reason: AIUnavailabilityReason

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.accentSoft)
                    .frame(width: 72, height: 72)

                Image(systemName: symbolName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.accent)
            }
            .glassCard(cornerRadius: 36)
            .accessibilityHidden(true)

            VStack(spacing: DesignTokens.Spacing.xs) {
                Text(L10n.localized("AI Features Unavailable", comment: "Title for AI unavailable state"))
                    .font(DesignTokens.Typography.title3.bold())
                    .multilineTextAlignment(.center)

                Text(reason.userFacingMessage)
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 320)

            if reason.hasAction {
                Button(reason.actionTitle) {
                    openSettings()
                }
                .glassButton()
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.xl)
    }

    private var symbolName: String {
        switch reason {
        case .deviceNotEligible:
            "iphone.slash"
        case .appleIntelligenceNotEnabled:
            "sparkles"
        case .modelNotReady:
            "hourglass"
        case .unknown:
            "exclamationmark.triangle"
        }
    }

    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        // Not the environment's `openURL`: inside AI Coach that action is replaced by the
        // model-link policy, which only admits https links and would discard this URL.
        UIApplication.shared.open(settingsURL)
    }
}

#Preview("Device Not Eligible") {
    AIAvailabilityBanner(reason: .deviceNotEligible)
        .padding(DesignTokens.Spacing.md)
}

#Preview("Not Enabled") {
    AIAvailabilityBanner(reason: .appleIntelligenceNotEnabled)
        .padding(DesignTokens.Spacing.md)
}

#Preview("Unavailable Full State") {
    AIUnavailableStateView(reason: .deviceNotEligible)
}
