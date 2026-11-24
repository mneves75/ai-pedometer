import Testing
@testable import AIPedometer

@Suite("AIModelAvailability")
struct AIModelAvailabilityTests {
    
    @Suite("isAvailable")
    struct IsAvailableTests {
        
        @Test("available returns true")
        func availableIsTrue() {
            let availability = AIModelAvailability.available
            #expect(availability.isAvailable == true)
        }
        
        @Test("checking returns false")
        func checkingIsFalse() {
            let availability = AIModelAvailability.checking
            #expect(availability.isAvailable == false)
        }
        
        @Test("unavailable returns false")
        func unavailableIsFalse() {
            let availability = AIModelAvailability.unavailable(reason:.deviceNotEligible)
            #expect(availability.isAvailable == false)
        }
    }
    
    @Suite("unavailabilityReason")
    struct UnavailabilityReasonTests {
        
        @Test("available returns nil")
        func availableReturnsNil() {
            let availability = AIModelAvailability.available
            #expect(availability.unavailabilityReason == nil)
        }
        
        @Test("checking returns nil")
        func checkingReturnsNil() {
            let availability = AIModelAvailability.checking
            #expect(availability.unavailabilityReason == nil)
        }
        
        @Test("unavailable returns reason")
        func unavailableReturnsReason() {
            let reason = AIUnavailabilityReason.appleIntelligenceNotEnabled
            let availability = AIModelAvailability.unavailable(reason:reason)
            #expect(availability.unavailabilityReason == reason)
        }
    }
}
