# Design System

Source: Shared/DesignSystem/DesignTokens.swift, GlassModifiers, AccessibilityModifiers, and current SwiftUI usage.
This file captures the design tokens and component styling currently implemented in code.

## Typography
- Typeface: System (SF) via SwiftUI default.
- Scale in use: .largeTitle, .title, .title2, .title3, .headline, .subheadline, .body, .callout, .caption, .caption2, .footnote.
- Numeric emphasis: .monospacedDigit() for stats and progress.
- Weight emphasis: .bold(), .weight(.medium), .weight(.semibold).

## Color
Semantic roles come from `DesignTokens.Colors` (accent, accentMuted, accentSoft, text and
surface roles). It resolves platform-specific values, because watchOS does not expose the
UIKit tertiary/quaternary label colors. Use the tokens rather than the raw SwiftUI colors
listed below, which describe current usage.

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

## Opacity Tokens
- textTertiary: 0.8
- textQuaternary: 0.6
- surfaceElevated: 0.06
- surfaceQuaternary: 0.04
- borderMuted: 0.12

## Point-Size Tokens
Explicit `.font(.system(size:))` values, used mostly for SF Symbol glyphs and for the large
hero numbers in onboarding, settings and the widgets. Body text uses the semantic scale above.
- xxl: 80, xl: 64, lg: 60, md: 48, sm: 44, xs: 40
- widgetLg: 36, widgetMd: 32, widgetSm: 30

## Shadows
There is no shadow token set. Elevation comes from glass surfaces and materials; the few
remaining `.shadow(...)` calls are local and should not be generalized into tokens without
a deliberate design pass.

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

## Icon Sizes
- xs: 20 (small inline accents)
- sm: 24 (chat avatars, accessory icons, list-row glyphs)
- md: 32 (settings rows, premium crown)
- lg: 36 (About feature/link badges)
- touchTarget: 44 (circular tappable badges, refresh buttons)
- hero: 100 (About hero circle)

## Component Sizing
- progressRing: 230, progressRingLineWidth: 16
- workoutCardWidth: 190
- routePreviewHeight: 104
- badgeCardMinHeight: 180 (uses minHeight for Dynamic Type)
- chartHeight: 150 (uses minHeight for Dynamic Type)
- chartBarMaxHeight: 120
- chatBubbleGutter: 40
- onboardingPageBottomInset: 132

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

## Using the tokens

New UI consumes tokens instead of literal `frame` and `cornerRadius` values; the enforcement
greps are `\.frame(width: [0-9]` and `cornerRadius: [0-9]`. Convert an existing literal only
when a token matches its exact value, so the edit is visually neutral. Widget chart and ring
geometry has no semantic token, and inventing one to satisfy the grep risks a layout regression.

## Patterns to repeat
- Route interactive accents through `DesignTokens.Colors.accent` rather than a literal color.
- Use the single `AIUnavailableStateView` for unavailable AI, so an expected state does not
  read as an error.
- Use capsule-plus-icon status badges for goal outcomes, and mute locked achievements with a
  subtle lock badge instead of a louder treatment.
- Prefer `minHeight` over a fixed `height` on text-bearing cards and charts so large Dynamic
  Type sizes do not clip.
