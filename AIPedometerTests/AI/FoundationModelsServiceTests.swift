import FoundationModels
import Testing
@testable import AIPedometer

/// Regression coverage for the 2026-07-20 iOS 27 device bug: the Dashboard banner showed
/// "Enable Apple Intelligence in Settings" while Apple Intelligence was ON. On-device syslog
/// proved `SystemLanguageModel.default.availability` changes WHILE the app runs (settings
/// re-evaluation, model assets finishing download), but the service snapshotted it at launch
/// and only re-read on foreground. These tests drive the injected system-availability seam
/// through the same handler the OS observation fires.
@Suite("FoundationModelsService")
@MainActor
struct FoundationModelsServiceTests {

    @Test("init maps every injected system unavailable reason")
    func initMapsInjectedUnavailableReasons() {
        let cases: [(SystemLanguageModel.Availability, AIUnavailabilityReason)] = [
            (.unavailable(.deviceNotEligible), .deviceNotEligible),
            (.unavailable(.appleIntelligenceNotEnabled), .appleIntelligenceNotEnabled),
            (.unavailable(.modelNotReady), .modelNotReady)
        ]
        for (systemValue, expectedReason) in cases {
            let service = FoundationModelsService(systemAvailability: { systemValue })
            #expect(service.availability == .unavailable(reason: expectedReason))
        }
    }

    @Test("init publishes available when the system model is available")
    func initPublishesAvailable() {
        let service = FoundationModelsService(systemAvailability: { .available })
        #expect(service.availability == .available)
    }

    @Test("system availability change handler publishes corrected state without relaunch")
    func systemAvailabilityChangeSelfHeals() {
        // Reproduces the reported bug: launch reads not-enabled, the system later flips to
        // available. The banner state must follow the system without an app relaunch.
        var current = SystemLanguageModel.Availability.unavailable(.appleIntelligenceNotEnabled)
        let service = FoundationModelsService(systemAvailability: { current })
        #expect(service.availability == .unavailable(reason: .appleIntelligenceNotEnabled))

        current = .available
        service.handleSystemAvailabilityChange()

        #expect(service.availability == .available)
    }

    @Test("system availability change handler publishes model-not-ready transition")
    func systemAvailabilityChangePublishesModelNotReady() {
        var current = SystemLanguageModel.Availability.unavailable(.modelNotReady)
        let service = FoundationModelsService(systemAvailability: { current })
        #expect(service.availability == .unavailable(reason: .modelNotReady))

        current = .available
        service.handleSystemAvailabilityChange()

        #expect(service.availability == .available)
    }

    @Test("system availability change to unavailable revokes published availability")
    func systemAvailabilityChangeToUnavailable() {
        var current = SystemLanguageModel.Availability.available
        let service = FoundationModelsService(systemAvailability: { current })
        #expect(service.availability == .available)

        current = .unavailable(.modelNotReady)
        service.handleSystemAvailabilityChange()

        #expect(service.availability == .unavailable(reason: .modelNotReady))
    }

    @Test("respond throws the mapped error while unavailable and stops throwing after self-heal")
    func respondReflectsLiveAvailability() async throws {
        var current = SystemLanguageModel.Availability.unavailable(.appleIntelligenceNotEnabled)
        let service = FoundationModelsService(systemAvailability: { current })

        do {
            _ = try await service.respond(to: "hello")
            Issue.record("Expected respond to throw while the model is unavailable")
        } catch let AIServiceError.modelUnavailable(reason) {
            #expect(reason == .appleIntelligenceNotEnabled)
        } catch {
            Issue.record("Unexpected error while unavailable: \(error)")
        }

        // After the system flips, the availability gate must reopen. The one-shot respond
        // itself still fails on the simulator (no on-device model), but it must NOT fail
        // with the unavailable error — a modelUnavailable throw here would prove the gate
        // stayed stale.
        current = .available
        service.handleSystemAvailabilityChange()
        #expect(service.availability.isAvailable)
    }
}
