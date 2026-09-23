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
- AI Insight card (if Apple Intelligence is available)
- Progress ring
- Stats grid with distance, calories, floors, latest heart rate, and streak
- Profile button routes to Settings

## History
- Weekly summary chart
- Weekly trend AI card (if Apple Intelligence is available)
- Daily history rows
- Empty/loading/error states

## Workouts
- Active workout banner (if active) -> ActiveWorkoutView sheet
- AI workout recommendation (if Apple Intelligence is available)
- Expedition Mode toggle for reduced live metrics cadence during long workouts
- Routes & GPX card for importing a route file and reviewing distance, estimated time, elevation gain, waypoints, and a MapKit route preview
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
- Empty state -> Create plan (AI generation needs Apple Intelligence)
- List of plans -> Plan detail
- CreatePlanSheet for new plan

## Badges
- Earned and Locked sections
- Badge celebration sheet when earned

## AI Coach
- Message list
- Suggested questions
- Input field and send action
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
- Version info

## More
- Badges
- Support AI Pedometer (opens About and the optional tip jar)
- Settings

## watchOS
- Step summary view

## Widgets
- Step Count widget
- Progress Ring widget
- Weekly Chart widget
- Live Activity widget
