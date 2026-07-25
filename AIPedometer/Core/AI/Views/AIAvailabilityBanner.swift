import SwiftUI
import UIKit

/// Banner that displays AI unavailability status with appropriate messaging and actions
struct AIAvailabilityBanner: View {
    let reason: AIUnavailabilityReason
    var onDismiss: (() -> Void)?
    
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: iconName)
                .font(DesignTokens.Typography.title2)
                .foregroundStyle(iconColor)
                .frame(width: DesignTokens.IconSize.md)
            
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(reason.userFacingMessage)
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                
                if reason.hasAction {
                    Button(action: openSettings) {
                        Text(reason.actionTitle)
                            .font(DesignTokens.Typography.subheadline.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
            
            Spacer()
            
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.title3)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .frame(width: DesignTokens.IconSize.touchTarget, height: DesignTokens.IconSize.touchTarget)
                .buttonStyle(.plain)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }
    
    private var iconName: String {
        switch reason {
        case .deviceNotEligible:
            "iphone.slash"
        case .appleIntelligenceNotEnabled:
            "brain"
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
        case .appleIntelligenceNotEnabled:
            DesignTokens.Colors.accent
        case .modelNotReady:
            DesignTokens.Colors.accent
        case .unknown:
            DesignTokens.Colors.warning
        }
    }
    
    private var backgroundColor: Color {
        switch reason {
        case .deviceNotEligible:
            DesignTokens.Colors.surfaceElevated
        case .appleIntelligenceNotEnabled:
            DesignTokens.Colors.accentSoft
        case .modelNotReady:
            DesignTokens.Colors.accentSoft
        case .unknown:
            DesignTokens.Colors.warning.opacity(0.12)
        }
    }
    
    private var borderColor: Color {
        switch reason {
        case .deviceNotEligible:
            DesignTokens.Colors.borderMuted
        case .appleIntelligenceNotEnabled:
            DesignTokens.Colors.accentMuted
        case .modelNotReady:
            DesignTokens.Colors.accentMuted
        case .unknown:
            DesignTokens.Colors.warning.opacity(0.3)
        }
    }
    
    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(settingsURL)
    }
}

/// Full-screen AI unavailable state with a friendly explanation and optional action
struct AIUnavailableStateView: View {
    let reason: AIUnavailabilityReason

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "sparkles.slash")
                .font(.system(size: DesignTokens.FontSize.md, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.accent)

            VStack(spacing: DesignTokens.Spacing.xs) {
                Text(L10n.localized("AI Features Unavailable", comment: "Title for AI unavailable state"))
                    .font(DesignTokens.Typography.title3.bold())

                Text(reason.userFacingMessage)
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if reason.hasAction {
                Button(reason.actionTitle) {
                    openSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.md)
    }

    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(settingsURL)
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

#Preview("Model Not Ready") {
    AIAvailabilityBanner(reason: .modelNotReady)
        .padding(DesignTokens.Spacing.md)
}

#Preview("Dismissible") {
    AIAvailabilityBanner(reason: .appleIntelligenceNotEnabled) { }
    .padding(DesignTokens.Spacing.md)
}
