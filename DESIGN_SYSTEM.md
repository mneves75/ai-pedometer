# Design System

Source: Shared/DesignSystem/DesignTokens.swift, GlassModifiers, AccessibilityModifiers, and current SwiftUI usage.
This file captures the design tokens and component styling currently implemented in code.

## Typography
- Typeface: System (SF) via SwiftUI default.
- Scale in use: .largeTitle, .title, .title2, .title3, .headline, .subheadline, .body, .callout, .caption, .caption2, .footnote.
- Numeric emphasis: .monospacedDigit() for stats and progress.
- Weight emphasis: .bold(), .weight(.medium), .weight(.semibold).

## Color
- Primary text: .primary
- Secondary text: .secondary
- Tertiary text: .tertiary
- Quaternary surfaces: Color(.quaternarySystemFill)
- Accent: .blue (tabs, primary highlights)
- AI accent: .purple (AI cards, AI icons)
- Success: .green
- Warning: .orange
- Error: .red
- Data colors: .mint, .cyan, .yellow, .blue, .purple
- Info/links: .blue
- Neutral backgrounds: Color(.systemGroupedBackground)
- Muted borders: Color(.systemGray4)
- Materials: .ultraThinMaterial, .bar
- Inverse text: Color.white
- Inverse stroke: Color.white opacity 0.15
- Overlays: Color.black opacity 0.4 / 0.3
- Gradients (current usage): blue/purple ring and blue gradient hero accents

## Spacing Tokens
- none: 0
- xxs: 2
- xs: 4
- xsPlus: 6
- sm: 8
- smPlus: 12
- md: 16
- mdPlus: 20
- lg: 24
- xl: 32
- xxl: 48

## Corner Radius Tokens
- xs: 4
- sm: 8
- md: 12
- lg: 16
- xl: 20
- xxl: 28

## Shadows
- subtle: black 8% opacity, radius 8, y 4
- medium: black 12% opacity, radius 16, y 8
- strong: black 18% opacity, radius 24, y 12

## Motion
- defaultDuration: 0.25
- shortDuration: 0.2
- longDuration: 0.35
- snappy: .snappy(duration: 0.25)
- smooth: .smooth(duration: 0.25)
- springy: .spring(response: 0.3, dampingFraction: 0.7)
- bouncy: .spring(response: 0.35, dampingFraction: 0.6)

## Touch Targets
- minimum: 44

## Surfaces and Components
- glassCard(cornerRadius, interactive):
  - iOS 26+: .glassEffect(.regular) or .glassEffect(.regular.interactive())
  - iOS < 26 and UI tests: .ultraThinMaterial background
- glassButton():
  - iOS 26+: .glassProminent
  - iOS < 26 and UI tests: .borderedProminent
- glassContainer(spacing): wraps children in GlassEffectContainer on iOS 26+

## Iconography
- SF Symbols only. Weight and size vary by context but remain within SF Symbols set.

## Haptics
- HapticService: tap, selection, confirm, success, warning, error.

## Accessibility Helpers
- accessibleButton(label, hint)
- accessibleCard(label, hint)
- accessibleProgress(label, value, total)
- accessibleStatistic(title, value)
