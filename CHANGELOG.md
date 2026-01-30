# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1] - 2026-01-29

Initial public release.

### Features

- **Step Tracking** — HealthKit integration with real-time pedometer and Apple Watch merging
- **AI Insights** — On-device AI analysis using Apple Foundation Models (no cloud, no data leaves device)
- **AI Coach** — Personalized coaching with structured responses via FoundationModelsService
- **AI Training Plans** — AI-generated walking programs adapted to fitness level
- **Workouts** — Active workout sessions with Live Activities and HealthKit recording
- **Badges & Achievements** — Unlockable badges with streak tracking
- **watchOS Companion** — Bidirectional sync via WatchConnectivity
- **Widgets** — Step count, progress ring, and weekly chart widgets (Lock Screen + Home Screen)
- **Accessibility** — Wheelchair push tracking mode, VoiceOver, Dynamic Type
- **Localization** — English and Portuguese Brazil (pt-BR)
- **Design System** — iOS 26 Liquid Glass support with unified design tokens and haptics

### Technical

- Swift 6.2 with strict concurrency (`complete` mode, warnings-as-errors)
- SwiftUI + SwiftData with App Group sharing across iOS, watchOS, and widgets
- Protocol-first architecture with `@MainActor @Observable` services
- XcodeGen for project generation
- Swift Testing framework for unit tests
- Background task scheduling for periodic sync
- DataConfidence pattern to prevent AI hallucination on unreliable data
