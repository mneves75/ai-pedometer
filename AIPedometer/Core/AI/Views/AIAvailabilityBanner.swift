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
                .frame(width: 32)
            
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
                .frame(width: 44, height: 44)
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

/// Compact inline banner for use in smaller spaces
struct AIAvailabilityInlineBanner: View {
    let reason: AIUnavailabilityReason
    
    var body: some View {
        Label {
            Text(reason.userFacingMessage)
                .font(DesignTokens.Typography.caption)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.Colors.warning)
        }
        .foregroundStyle(DesignTokens.Colors.textSecondary)
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
                Text(String(localized: "AI Features Unavailable", comment: "Title for AI unavailable state"))
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

/// Loading state view for AI operations
struct AILoadingView: View {
    let message: String
    
    init(_ message: String = String(localized: "Thinking...", comment: "AI loading default message")) {
        self.message = message
    }
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ProgressView()
                .controlSize(.small)
            
            Text(message)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(DesignTokens.Spacing.md)
    }
}

/// View modifier to conditionally show AI unavailability banner
struct AIAvailabilityModifier: ViewModifier {
    let availability: AIModelAvailability
    @State private var isDismissed = false
    
    func body(content: Content) -> some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            if case .unavailable(let reason) = availability, !isDismissed {
                AIAvailabilityBanner(reason: reason) {
                    withAnimation(DesignTokens.Animation.smooth) {
                        isDismissed = true
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            content
        }
        .animation(DesignTokens.Animation.smooth, value: isDismissed)
    }
}

extension View {
    /// Shows an AI availability banner at the top of the view if AI is unavailable
    func aiAvailabilityBanner(_ availability: AIModelAvailability) -> some View {
        modifier(AIAvailabilityModifier(availability: availability))
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

#Preview("Inline") {
    AIAvailabilityInlineBanner(reason: .modelNotReady)
        .padding(DesignTokens.Spacing.md)
}

#Preview("Loading") {
    AILoadingView("Generating insight...")
        .padding(DesignTokens.Spacing.md)
}
