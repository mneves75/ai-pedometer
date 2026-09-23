# App Store Metadata - en-US

Canonical upload files: `store/app-store/` (`asc metadata` format, validated with
`asc metadata validate --dir store/app-store --check-urls --subscription-app`).

## App Information

- Primary Category: `Health & Fitness`
- Secondary Category: `Lifestyle`
- Price: paid download, `R$ 1,99` in the Brazil base territory (price point in `store/app-store/pricing.json`), other territories equalized by Apple

## Listing text

Name, subtitle, promotional text, description, keywords and the marketing, privacy and support URLs live in
`store/app-store/app-info/en-US.json` and `store/app-store/version/<version>/en-US.json`.
The first App Store release has no What's New text.

## License Agreement

- License Agreement: Apple's standard EULA (`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`), linked in the description and in the paywall

## App Privacy

- Data type: `Purchases > Purchase History`
- Purposes: `App Functionality`, `Analytics`
- Linked to identity: `No` (RevenueCat anonymous App User ID; the app has no account)
- Used for tracking: `No`
- Health & Fitness collection: `No`

## App Review Information

- Demo account required: `No`
- Sign-in required: `No`
- Review notes:
  - `Tip Jar (consumable IAP): com.mneves.aipedometer.coffee`
  - `Premium products: com.mneves.aipedometer.premium.monthly and com.mneves.aipedometer.premium.yearly`
  - `Premium AI subscription entitlement: premium`
  - `AI processing is on-device via Apple Foundation Models; no cloud AI service is used.`
  - `Premium Expedition Mode and GPX route import are available in the Workouts tab.`
  - `Premium access paths: Workouts > Expedition Mode / Routes & GPX; More > Support AI Pedometer > Premium`
  - `Tip Jar access path: More > Support AI Pedometer > Buy me a coffee`
  - `Restore Purchases and Manage Subscription are available on the Premium sheet.`

## Screenshot set (suggested order)

1. Dashboard
2. AI Coach
3. Workouts
4. Training Plans
5. History
6. Badges
7. Active Workout
8. About - Tip Jar
