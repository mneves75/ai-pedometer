# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | Yes       |
| < 1.0   | No        |

## Reporting a Vulnerability

This repository is public. If you discover a security vulnerability:

1. **Do not** create a public issue with exploit details.
2. Use GitHub private vulnerability reporting (Security Advisories):
   - https://github.com/mneves75/ai-pedometer/security/advisories/new
3. Include clear reproduction steps, impact, affected versions, and proof-of-concept.
4. Allow coordinated disclosure time for triage, fix, and release.

### Response Targets

- Initial triage acknowledgment: within 72 hours
- Risk assessment and mitigation plan: within 7 business days
- Coordinated disclosure after patch and release notes

## Security Practices

This project follows security best practices:

- **HealthKit Data**: All health data stays on-device; no external transmission
- **AI Processing**: On-device only via Apple Foundation Models; no cloud AI
- **Entitlements**: Minimal permissions requested (HealthKit, App Groups only)
- **No Advertising/Behavioral Analytics**: No ad tracking, behavioral analytics or third-party SDK that receives user data
- **Private Logs**: Structured log metadata is redacted by default before OSLog emission
- **Privacy Manifests**: `NSPrivacyCollectedDataTypes` is empty because Health/Fitness values stay on-device and are not collected by the developer
- **Strict Concurrency**: Swift 6.2 data-race safety enforced at compile time

## Data Privacy

- Health data is accessed via HealthKit APIs with user consent
- Health/Fitness processing occurs locally on the user's device
- The app sends no data to the developer or third parties; Apple processes the App Store purchase and the optional Tip Jar under its own policy
- The App Store privacy label is "Data Not Collected" (`store/app-store/privacy.json`), consistent with the empty privacy-manifest collection arrays
- App-group UserDefaults access is declared with the Apple-required reason for shared app/widget/watch state
- Local data (the SwiftData store, the imported GPX route and the shared step snapshot) uses iOS's default
  Data Protection class, protected until the first unlock after boot. Stricter `.complete` protection is a
  deliberate non-goal: background refresh and the Lock Screen widgets read that data while the device is locked
- See Apple's [HealthKit privacy documentation](https://developer.apple.com/documentation/healthkit/protecting_user_privacy)
