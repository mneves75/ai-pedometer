# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.76.x  | Yes       |
| < 0.76  | No        |

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
- **No Analytics**: No third-party tracking or telemetry
- **Private Logs**: Structured log metadata is redacted by default before OSLog emission
- **Privacy Manifests**: Health/Fitness collection uses Apple's official privacy manifest identifiers and app functionality purpose only
- **Strict Concurrency**: Swift 6.2 data-race safety enforced at compile time

## Data Privacy

- Health data is accessed via HealthKit APIs with user consent
- All data processing occurs locally on the user's device
- No personal data is transmitted to external servers
- App-group UserDefaults access is declared with the Apple-required reason for shared app/widget/watch state
- See Apple's [HealthKit privacy documentation](https://developer.apple.com/documentation/healthkit/protecting_user_privacy)
