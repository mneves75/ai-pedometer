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

## Age Rating and Content Rights

- Age rating: every item `None`/`No` except Health or Wellness Topics = `Yes` (exercise recommendations),
  which rates the app 9+. The AI Coach is not Messaging and Chat, which Apple defines as users talking to
  each other, and links open outside the app, so there is no Unrestricted Web Access.
- Content rights: `Does not use third-party content`.

## App Review Information

- Demo account required: `No`
- Sign-in required: `No`
- Review notes: `store/app-store/review.json` (applied verbatim; `StoreListingTests` keeps the removed Premium
  plan out of them). The contact is set only in App Store Connect.
- Tip Jar: consumable `com.mneves.aipedometer.coffee` (`store/app-store/tip-jar.json`), More > Support AI
  Pedometer > Buy me a coffee. As the app's first in-app purchase it goes to review with the app version.

## Screenshots uploaded for 1.0.8

- iPhone 6.5" (captured at 6.9"): Dashboard, AI Coach, Workouts, Training Plans, History, Badges, Onboarding.
- iPad 13": Dashboard, History, Workouts, Badges.
- Apple Watch: 416x496 captures of the watch step summary (required because the app embeds a watch app).
- Captured from a Debug build with demo data and on-device AI. Tip Jar and Active Workout are left out
  because a simulator shows no price and cannot start a workout session.
