# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.6.x   | Yes       |
| < 0.6   | No        |

## Reporting a Vulnerability

This is a private repository. If you discover a security vulnerability:

1. **Do not** create a public issue
2. Contact the repository owner directly
3. Include detailed information about the vulnerability
4. Allow reasonable time for a fix before any disclosure

## Security Practices

This project follows security best practices:

- **HealthKit Data**: All health data stays on-device; no external transmission
- **AI Processing**: On-device only via Apple Foundation Models; no cloud AI
- **Entitlements**: Minimal permissions requested (HealthKit, App Groups only)
- **No Analytics**: No third-party tracking or telemetry
- **Strict Concurrency**: Swift 6.2 data-race safety enforced at compile time

## Data Privacy

- Health data is accessed via HealthKit APIs with user consent
- All data processing occurs locally on the user's device
- No personal data is transmitted to external servers
- See Apple's [HealthKit privacy documentation](https://developer.apple.com/documentation/healthkit/protecting_user_privacy)
