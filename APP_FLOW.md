# App Flow

This flow is derived from current SwiftUI navigation and tabs.

## Onboarding
1. Welcome
2. Daily goal setup
3. Permissions
4. Completion sets onboardingCompleted and routes to MainTabView

## Main Navigation (iPhone)
Tabs:
- Dashboard
- History
- Workouts
- AI Coach
- More

## Main Navigation (iPad)
NavigationSplitView sidebar:
- Dashboard
- History
- Workouts
- Badges
- AI Coach
- Settings

## Dashboard
- Daily header
- Premium-gated AI Insight card (if premium and AI are available)
- Progress ring
- Stats grid
- Profile button routes to Settings

## History
- Weekly summary chart
- Premium-gated weekly trend AI card (if premium and AI are available)
- Daily history rows
- Empty/loading/error states

## Workouts
- Active workout banner (if active) -> ActiveWorkoutView sheet
- Premium-gated AI workout recommendation (if premium and AI are available)
- Start workout action
- Training Plans card -> TrainingPlansView
- Recent workouts carousel

## Active Workout (Sheet)
- Status header
- Metrics grid
- Target progress (if target steps)
- Pause/Resume and End actions
- Discard action (toolbar)

## Training Plans
- Empty state -> Create plan (premium-gated for AI generation)
- List of plans -> Plan detail
- CreatePlanSheet for new plan

## Badges
- Earned and Locked sections
- Badge celebration sheet when earned

## AI Coach
- Message list
- Suggested questions
- Input field and send action
- Premium gate before coach access when entitlement is unavailable
- AI availability banner and disclaimer

## Settings
- Daily goal editor sheet
- Activity tracking mode
- Distance estimation mode
- Notifications + Smart reminders
- HealthKit sync
- About row -> AboutView
- Debug section in DEBUG builds

## About
- Hero and feature cards
- Links (App Store review, feedback, privacy policy)
- Support (tip jar) section
- Premium subscription status, restore/manage actions, and RevenueCat Customer Center when available
- Version info

## More
- Links to Badges and Settings

## watchOS
- Step summary view

## Widgets
- Step Count widget
- Progress Ring widget
- Weekly Chart widget
- Live Activity widget
