# FOR_YOU_KNOW.md

This project is a pedometer app, but that description undersells what is really here.

Think of it as three products sharing one nervous system:

1. an iPhone app that tracks movement and turns it into a calm daily dashboard
2. a watch companion that shows the important bits without ceremony
3. a set of widgets and Live Activities that keep the app visible even when it is not open

Then there is the extra twist: it also tries to be a private, on-device AI coach. No cloud round-trips. No "send your health data somewhere and hope for the best." The codebase is built around that promise.

## The big picture

If you want one mental model for the whole app, use this:

"HealthKit is the source of truth, `StepTrackingService` is the traffic cop, SwiftUI is the storefront, and the watch/widgets are satellite displays."

Most of the repository makes sense once you see that pattern.

## How the app starts

The front door is [`AIPedometer/App/AIPedometerApp.swift`](AIPedometer/App/AIPedometerApp.swift). This file is not just app boilerplate. It is the composition root. It creates the major services once, wires them together, and injects the resulting shared state into the app.

That matters because this app has a lot of moving parts:

- HealthKit authorization
- motion fallback behavior
- shared app-group data
- on-device AI services
- workout tracking
- notifications
- premium access state
- watch sync
- background refresh

`AIPedometerApp` builds these pieces up front so the rest of the app can behave like a coherent system instead of a pile of independently invented singletons.

Two coordinator objects keep startup civilized:

- [`AIPedometer/App/AppStartupCoordinator.swift`](AIPedometer/App/AppStartupCoordinator.swift) handles the one-time "get the engine running" sequence
- `AppLifecycleCoordinator` handles refresh work when the app comes back into the foreground

This is a good engineering choice. It keeps startup policy out of random views and stops lifecycle logic from leaking everywhere.

## Navigation: what users actually see

[`AIPedometer/Features/RootView.swift`](AIPedometer/Features/RootView.swift) decides whether the user goes through onboarding or lands in the main app.

After that, [`AIPedometer/Features/MainTabView/MainTabView.swift`](AIPedometer/Features/MainTabView/MainTabView.swift) takes over:

- iPhone gets a `TabView`
- iPad gets a `NavigationSplitView`

That split is worth remembering. If a navigation bug appears only on one device class, do not assume the other layout proves anything. They share concepts, not the same container code.

The main product areas are straightforward and intentionally product-shaped:

- Dashboard
- History
- Workouts
- AI Coach
- Badges
- Settings
- More

`APP_FLOW.md` is the quick map. The feature directories under `AIPedometer/Features/` are the street-level detail.

## The heart of the app: step tracking

If the app were a small city, [`AIPedometer/Core/StepTracking/StepTrackingService.swift`](AIPedometer/Core/StepTracking/StepTrackingService.swift) would be the traffic control center.

It is responsible for:

- refreshing today's numbers
- deciding when to fall back from HealthKit to Motion
- calculating distance, floors, calories, and streak-related state
- updating shared data used by widgets and the watch
- refreshing weekly summaries
- triggering badge evaluation

This service is the place where "raw activity inputs" become "product behavior."

That is an important distinction. HealthKit tells you facts. `StepTrackingService` decides what the app should do with those facts.

## Health data: source of truth, with a parachute

[`AIPedometer/Core/HealthKit/HealthKitService.swift`](AIPedometer/Core/HealthKit/HealthKitService.swift) is the direct bridge into HealthKit. It fetches steps, wheelchair pushes, distance, floors, summaries, and workout data.

But the more revealing file is [`AIPedometer/Core/HealthKit/HealthKitServiceFallback.swift`](AIPedometer/Core/HealthKit/HealthKitServiceFallback.swift).

That file tells you what kind of engineers built this app. They expected reality to be messy:

- permissions can be denied
- HealthKit can be unavailable
- test and demo flows need deterministic behavior
- the product still needs to behave gracefully

So instead of pretending the happy path is the only path, the app has an explicit fallback wrapper. That is good product engineering. The user sees "the app still behaves sensibly" instead of "one missing entitlement turned the whole screen into nonsense."

There is also a subtle product truth here: health apps live and die on trust. Returning empty or degraded states deliberately is often better than inventing confidence the system does not have.

## AI: the fancy part, grounded by constraints

The AI layer starts in [`AIPedometer/Core/AI/FoundationModelsService.swift`](AIPedometer/Core/AI/FoundationModelsService.swift).

This file does two jobs:

1. checks whether Apple Foundation Models are available on the current device
2. wraps prompt/response behavior for both plain-text and structured generation

Around it sit specialized services:

- `InsightService`
- `CoachService`
- `TrainingPlanService`
- `SmartNotificationService`

These live under `AIPedometer/Core/AI/Services/`.

The important design choice is that the code does not treat "AI" like one giant magical box. It treats AI as a lower-level capability, then builds product-specific services on top of it.

That is the difference between a demo and a real app.

Another good sign: the default instructions explicitly avoid medical advice and health claims. That is not just legal hygiene. It is product discipline.

## Premium access: the business layer without pretending it is the product

The revenue system lives under `AIPedometer/Core/Monetization/`.

[`AIPedometer/Core/Monetization/PremiumAccessStore.swift`](AIPedometer/Core/Monetization/PremiumAccessStore.swift) is the key file to understand. It integrates RevenueCat, tracks offerings and entitlement state, and decides whether premium AI features are actually available.

One design decision is especially worth preserving: premium fails closed.

If RevenueCat is not configured, the app does not quietly leak premium capability. It moves into a "not configured" or unavailable state and keeps the boundary intact.

That is the right instinct. Billing bugs are trust bugs.

Also note the current doc drift: `PRD.md` still says subscriptions are out of scope, but the codebase and `README.md` clearly show premium gating is already part of reality. When docs and code disagree, trust the code first, then fix the docs.

## Watch and widgets: the satellites

The watch app is intentionally thin. It is not trying to recreate the whole phone experience.

Two files tell the story:

- [`AIPedometer/Core/WatchConnectivity/WatchSyncService.swift`](AIPedometer/Core/WatchConnectivity/WatchSyncService.swift)
- [`AIPedometerWatch/WatchSyncClient.swift`](AIPedometerWatch/WatchSyncClient.swift)

The phone sends snapshots of the important state. The watch receives them and updates its local payload. That keeps the watch experience lightweight and practical.

The widget target follows the same philosophy. It does not invent a separate product model. It consumes shared models and shared storage so the widgets remain extensions of the main app instead of little forked apps living in denial.

That shared-code strategy is visible across:

- `Shared/Models/`
- `Shared/Utilities/`
- `Shared/Constants/`
- `Shared/DesignSystem/`

When something needs to work consistently across iPhone, watch, and widgets, the right first question is usually: "should this live in `Shared/`?"

## Persistence and shared state

The repository uses SwiftData for persistence and the Observation framework for app state.

That is a modern Apple-stack choice and it fits the rest of the repo:

- SwiftUI views consume observable state
- persisted models back history, goals, plans, and related product features
- app-group-backed storage keeps extensions in sync

You can think of it this way:

- SwiftData remembers the story
- Observation keeps the UI alive
- app-group storage keeps the side screens honest

## Build system and repo layout

This repo is generated by XcodeGen from [`project.yml`](project.yml), not maintained as a hand-edited `.pbxproj` artifact.

That is a major practical detail. If a target, entitlement, package, or setting seems wrong, check `project.yml` first. Do not waste time debugging generated output that will be rewritten on the next project generation.

Important layout anchors:

- `AIPedometer/`: app code
- `Shared/`: cross-target shared code
- `AIPedometerWatch/`: watchOS app
- `AIPedometerWidgets/`: widget extension
- `AIPedometerTests/`: unit tests
- `AIPedometerUITests/`: UI tests
- `Scripts/`: operational scripts
- `Config/`: xcconfig setup and local overrides

## Testing philosophy: the repo is already telling you what "good" looks like

The test suite is broad and feature-shaped:

- AI tests
- localization tests
- persistence tests
- design-system tests
- workout tests
- HealthKit and sync tests
- startup/lifecycle tests

That is a clue. This team already believes in protecting behavior with targeted tests, not just poking around manually.

So when a bug report comes in, the correct posture is not "where do I patch this quickly?"

It is:

1. where should the regression live?
2. how do I make the failure undeniable?
3. what is the narrowest production fix that makes the test pass?

That is not bureaucracy. It is how you stop the same bug from coming back wearing a different hat.

## Landmines and pitfalls

Here are the things most likely to waste time if you forget them.

### 1. Doc drift is real here

This repo already had references to `AGENTS.md` and `CLAUDE.md` in `README.md` before those files existed locally. `PRD.md` also trails the code on premium features.

Lesson: docs are useful, but they are not always current. Verify against real files before repeating a claim.

### 2. "Executed 0 tests" is not success

From prior repo work, one of the easiest ways to lie to yourself on Apple platforms is to run the wrong scheme or destination and walk away with a technically green command that validated nothing meaningful.

If no real tests ran, you have no evidence.

### 3. Hardcoded build paths are a trap

For install and packaging flows, derive paths from build settings instead of guessing DerivedData paths by habit. Generated Apple build outputs have a way of punishing assumptions.

### 4. Simulator concurrency can create fake mysteries

Running overlapping simulator test jobs against the same destination is a good way to manufacture crashes that look like app bugs but are really toolchain contention.

Serialize when the tooling is the variable under test.

### 5. Health apps need graceful degradation

If a fix "works" only when every permission and entitlement is present, it is probably not finished. This app already bakes in fallback behavior. Respect that design instead of bulldozing it.

## Why the repo feels solid

The strongest thing about this project is that it is not built like a toy demo wearing production clothing.

You can see the discipline in the seams:

- startup is coordinated
- platform-specific work is isolated
- cross-target logic is shared deliberately
- AI has guardrails
- premium boundaries fail closed
- tests are organized around behaviors users actually care about

Good engineers do not just make features appear. They make the edges boring. This repo has a lot of that energy.

## How to work on it without making it worse

When you touch this codebase:

- start by confirming repo scope
- read the local memory files first
- trust `project.yml` more than generated Xcode artifacts
- add regression tests before bug fixes
- check real file locations before quoting docs
- preserve fail-closed behavior in AI, health, and premium boundaries
- keep shared logic in `Shared/` when multiple targets depend on it

If you remember only one thing, remember this:

This app is less like a single screen stack and more like a small transit system. Phone, watch, widgets, AI, HealthKit, and premium state are all connected. A local change can ripple outward fast. Work like a signal engineer, not like someone swapping light bulbs in isolation.

