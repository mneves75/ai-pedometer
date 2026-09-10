import Foundation
import Testing

@testable import AIPedometer

struct WorkoutTypeTests {
    @Test
    func iconIsValidSFSymbol() {
        for type in WorkoutType.allCases {
            #expect(!type.icon.isEmpty)
            #expect(type.icon.contains("figure"))
        }
    }
}
