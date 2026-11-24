import Foundation
import Testing
import UIKit

@testable import AIPedometer

struct WorkoutTypeTests {
    @Test("Every WorkoutType icon resolves to an actual SF Symbol", arguments: WorkoutType.allCases)
    func iconIsValidSFSymbol(type: WorkoutType) {
        #expect(UIImage(systemName: type.icon) != nil, "Invalid SF Symbol: \(type.icon)")
    }
}
