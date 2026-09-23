# App Store Metadata - en-US

Canonical upload files: `store/app-store/` (`asc metadata` format, validated with
`asc metadata validate --dir store/app-store --check-urls`).

## App Information

- Primary Category: `Health & Fitness`
- Secondary Category: `Lifestyle`
- Price: paid download, `R$ 1,99` in the Brazil base territory (price point in `store/app-store/pricing.json`), other territories equalized by Apple

## Listing text

Name, subtitle, promotional text, description, keywords and the marketing, privacy and support URLs live in
`store/app-store/app-info/en-US.json` and `store/app-store/version/<version>/en-US.json`.
The first App Store release has no What's New text.

## License Agreement

- License Agreement: Apple's standard EULA (applies automatically; the app has no subscription)

## App Privacy

Canonical file: `store/app-store/privacy.json` (`asc web privacy` format).

- Data collection: `Data Not Collected`. Nothing is sent to the developer or third parties; Apple processes
  the App Store purchase and the optional tip as an independent controller.
- Used for tracking: `No`

## App Review Information

- Demo account required: `No`
- Sign-in required: `No`
- Review notes:
  - `Paid app (one-time purchase). There is no subscription: every feature is available without further purchase.`
  - `Only in-app purchase: optional Tip Jar (consumable), com.mneves.aipedometer.coffee. It unlocks nothing.`
  - `Tip Jar access path: More > Support AI Pedometer > Buy me a coffee`
  - `AI processing is on-device via Apple Foundation Models; no cloud AI service is used. AI features need a device with Apple Intelligence turned on.`
  - `Expedition Mode and GPX route import are in the Workouts tab.`

## Screenshot set (suggested order)

1. Dashboard
2. AI Coach
3. Workouts
4. Training Plans
5. History
6. Badges
7. Active Workout
8. About - Tip Jar
