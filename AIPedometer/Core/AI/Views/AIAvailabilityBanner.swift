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
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(reason.userFacingMessage)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                
                if reason.hasAction {
                    Button(action: openSettings) {
                        Text(reason.actionTitle)
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
            
            Spacer()
            
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
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
            .gray
        case .appleIntelligenceNotEnabled:
            .orange
        case .modelNotReady:
            .blue
        case .unknown:
            .yellow
        }
    }
    
    private var backgroundColor: Color {
        switch reason {
        case .deviceNotEligible:
            Color(.systemGray6)
        case .appleIntelligenceNotEnabled:
            Color.orange.opacity(0.1)
        case .modelNotReady:
            Color.blue.opacity(0.1)
        case .unknown:
            Color.yellow.opacity(0.1)
        }
    }
    
    private var borderColor: Color {
        switch reason {
        case .deviceNotEligible:
            Color(.systemGray4)
        case .appleIntelligenceNotEnabled:
            Color.orange.opacity(0.3)
        case .modelNotReady:
            Color.blue.opacity(0.3)
        case .unknown:
            Color.yellow.opacity(0.3)
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
                .font(.caption)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
        .foregroundStyle(.secondary)
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Spacing.md)
    }
}

/// View modifier to conditionally show AI unavailability banner
struct AIAvailabilityModifier: ViewModifier {
    let availability: AIModelAvailability
    @State private var isDismissed = false
    
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
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
        .padding()
}

#Preview("Not Enabled") {
    AIAvailabilityBanner(reason: .appleIntelligenceNotEnabled)
        .padding()
}

#Preview("Model Not Ready") {
    AIAvailabilityBanner(reason: .modelNotReady)
        .padding()
}

#Preview("Dismissible") {
    AIAvailabilityBanner(reason: .appleIntelligenceNotEnabled) { }
    .padding()
}

#Preview("Inline") {
    AIAvailabilityInlineBanner(reason: .modelNotReady)
        .padding()
}

#Preview("Loading") {
    AILoadingView("Generating insight...")
        .padding()
}
