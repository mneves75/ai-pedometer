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
    
    @Suite("Equatable")
    struct EquatableTests {
        
        @Test("available equals available")
        func availableEqualsAvailable() {
            #expect(AIModelAvailability.available == AIModelAvailability.available)
        }
        
        @Test("checking equals checking")
        func checkingEqualsChecking() {
            #expect(AIModelAvailability.checking == AIModelAvailability.checking)
        }
        
        @Test("unavailable equals unavailable with same reason")
        func unavailableEqualsSameReason() {
            let a = AIModelAvailability.unavailable(reason:.deviceNotEligible)
            let b = AIModelAvailability.unavailable(reason:.deviceNotEligible)
            #expect(a == b)
        }
        
        @Test("unavailable differs with different reason")
        func unavailableDiffersDifferentReason() {
            let a = AIModelAvailability.unavailable(reason:.deviceNotEligible)
            let b = AIModelAvailability.unavailable(reason:.modelNotReady)
            #expect(a != b)
        }
        
        @Test("available differs from unavailable")
        func availableDiffersFromUnavailable() {
            #expect(AIModelAvailability.available != AIModelAvailability.unavailable(reason:.unknown))
        }
    }
}
