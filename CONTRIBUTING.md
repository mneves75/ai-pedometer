# Contributing to AIPedometer

Thank you for your interest in contributing to AIPedometer! This project showcases Apple Foundation Models for on-device AI in an iOS pedometer app.

## Getting Started

### Prerequisites

- macOS 15+ (Sequoia)
- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Setup

```bash
# Clone the repository
git clone https://github.com/mneves75/ai-pedometer.git
cd ai-pedometer

# Install XcodeGen
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Open project
open AIPedometer.xcodeproj
```

## Development

### Architecture

- **Swift 6.2** with strict concurrency
- **SwiftUI** for all UI
- **SwiftData** for persistence
- **Apple Foundation Models** for on-device AI

### Code Style

- Follow Swift conventions
- Use `@MainActor @Observable` for services
- Structured logging with `Loggers.category.level()`
- Protocol-first design for testability

### Running Tests

```bash
# All tests
xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' test

# Unit tests only
xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AIPedometerTests
```

## Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes with [conventional commits](https://conventionalcommits.org)
4. Push to your fork
5. Open a Pull Request

### PR Checklist

- [ ] Tests pass locally
- [ ] Code follows existing patterns
- [ ] Localized strings added to `Localizable.xcstrings`
- [ ] CHANGELOG.md updated for user-facing changes

## Reporting Issues

Use GitHub Issues with the provided templates for:
- Bug reports
- Feature requests

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.
