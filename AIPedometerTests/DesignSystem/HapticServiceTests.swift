#if os(iOS)
import Testing

@testable import AIPedometer

@Suite("HapticService Tests")
struct HapticServiceTests {

    @Test("Haptic calls do not crash on iOS")
    @MainActor
    func hapticCallsDoNotCrash() {
        let service = HapticService.shared

        // These should execute without crashing
        // Actual haptic feedback requires device, but API calls should be safe
        service.tap()
        service.selection()
        service.confirm()
        service.success()
        service.warning()
        service.error()
    }

    @Test("Impact with specific style does not crash")
    @MainActor
    func impactWithStyleDoesNotCrash() {
        let service = HapticService.shared

        // Test all feedback styles
        service.impact(.light)
        service.impact(.medium)
        service.impact(.heavy)
        service.impact(.soft)
        service.impact(.rigid)
    }

    @Test("Singleton is consistent")
    @MainActor
    func singletonIsConsistent() {
        let first = HapticService.shared
        let second = HapticService.shared

        // Both references should point to the same instance
        #expect(first === second)
    }
}
#endif
