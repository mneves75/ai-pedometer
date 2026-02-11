# AIPedometer

> Open source iOS pedometer showcasing Apple Foundation Models on-device AI

[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2026%2B%20%7C%20watchOS%2026%2B-blue.svg)](https://developer.apple.com/ios/)
[![Xcode](https://img.shields.io/badge/Xcode-26-blue.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

## Overview

AIPedometer is a modern step tracking application featuring **on-device AI coaching** powered by Apple Foundation Models. All AI processing happens locally on your device—no cloud APIs, no data leaving your phone.

### Key Features

- **Step Tracking** — HealthKit integration with real-time pedometer and Apple Watch merging
- **AI Insights** — On-device AI analysis using Apple Foundation Models
- **AI Coach** — Personalized coaching and training plans
- **AI Training Plans** — AI-generated workout programs adapted to your fitness level
- **watchOS App** — Companion app with bidirectional sync
- **Widgets** — Lock screen and Home Screen widgets
- **Accessibility** — Wheelchair mode for push tracking, VoiceOver support
- **Tip Jar** — Optional one-time “Buy me a coffee” support (USD $4.99 in the US)

## Requirements

| Dependency | Version |
|------------|---------|
| iOS | 26.0+ |
| watchOS | 26.0+ |
| Xcode | 26.0+ |
| Swift | 6.2 |

## Quick Start

```bash
# Install XcodeGen (if needed)
brew install xcodegen

# Generate Xcode project
xcodegen generate && Scripts/restore-entitlements.sh

# Open project
open AIPedometer.xcodeproj
```

## Project Structure

```
├── AIPedometer/           # Main iOS app
│   ├── App/               # App entry point, lifecycle
│   ├── Core/              # Services (AI, HealthKit, Persistence, etc.)
│   └── Features/          # Feature modules (Dashboard, History, etc.)
├── AIPedometerWatch/      # watchOS companion app
├── AIPedometerWidgets/    # iOS widgets (Lock Screen, Home Screen)
├── AIPedometerTests/      # Unit tests (Swift Testing)
├── AIPedometerUITests/    # UI tests
├── Shared/                # Cross-target code (Models, DesignSystem, Utilities)
├── StoreKit/              # StoreKit Configuration for tip jar testing
├── Scripts/               # Build and utility scripts
└── project.yml            # XcodeGen configuration
```

## Development

### Build & Test

```bash
# Build for simulator
xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' build

# Run all tests
xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' test

# Run specific test file
xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:AIPedometerTests/DailyStepCalculatorTests
```

### Configuration

Swift 6.2 strict concurrency is enforced project-wide:

- `SWIFT_STRICT_CONCURRENCY: complete`
- `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES`
- `GCC_TREAT_WARNINGS_AS_ERRORS: YES`

### Localization

Supports English (en) and Portuguese Brazil (pt-BR) via String Catalogs.

## Documentation

| Document | Purpose |
|----------|---------|
| [CLAUDE.md](CLAUDE.md) | AI assistant guidance for codebase |
| [CHANGELOG.md](CHANGELOG.md) | Version history and release notes |
| [AGENTS.md](AGENTS.md) | Agent guidelines and workflows |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution guidelines |
| `DESIGN_SYSTEM.md` / `FRONTEND_GUIDELINES.md` | UI tokens and UI engineering conventions |

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Version

**Current**: 0.4.20

See [CHANGELOG.md](CHANGELOG.md) for release history.

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.
