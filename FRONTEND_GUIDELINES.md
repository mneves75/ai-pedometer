# Frontend Guidelines

This document summarizes the current SwiftUI component and styling conventions used in the app.

## Architecture and State
- SwiftUI views live under AIPedometer/Features.
- Shared UI helpers and tokens live under Shared/DesignSystem.
- Services are injected via @Environment(ServiceType.self).
- View-local state uses @State; shared state uses @Observable services.

## Styling and Layout
- Use DesignTokens for spacing, corner radius, and animation values.
- Use glassCard and glassButton modifiers for primary surfaces and actions.
- Use GlassEffectContainer (via glassContainer) to group glass elements on iOS 26+.
- Backgrounds use Color(.systemGroupedBackground) unless a screen-specific surface is required.
- Materials use .ultraThinMaterial for cards and .bar for input surfaces.

## Typography
- System font only (SwiftUI default).
- Use the built-in SwiftUI scale: largeTitle, title, title2, title3, headline, subheadline, caption, caption2, footnote.
- Use .monospacedDigit() for numeric displays.

## Color Usage
- Primary emphasis: .blue and .primary.
- AI emphasis: .purple.
- Success: .green, warning: .orange, error: .red.
- Secondary copy uses .secondary or .tertiary.

## Motion
- Use DesignTokens.Animation for transitions and view animations.
- Avoid animations during UI tests via LaunchConfiguration.isUITesting and applyIfNotUITesting.

## Accessibility
- Use accessibleButton, accessibleCard, accessibleProgress, accessibleStatistic helpers where relevant.
- Ensure touch targets are at least DesignTokens.TouchTarget.minimum.
- Provide accessibility identifiers for UI tests on key interactive elements.

## Localization
- All user-facing strings use String(localized:) or Localization.format.
- String catalog: Shared/Resources/Localizable.xcstrings (en, pt-BR).

## Testing Considerations
- LaunchConfiguration.isUITesting disables glass effects and certain animations.
- Avoid relying on animation timing for layout-critical UI tests.
