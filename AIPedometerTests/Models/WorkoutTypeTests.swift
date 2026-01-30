import Foundation
import Testing

@testable import AIPedometer

struct WorkoutTypeTests {
    @Test
    func allCasesHaveDistinctRawValues() {
        let rawValues = WorkoutType.allCases.map(\.rawValue)
        let uniqueValues = Set(rawValues)
        #expect(rawValues.count == uniqueValues.count)
    }

    @Test
    func encodesAndDecodesCorrectly() throws {
        for type in WorkoutType.allCases {
            let encoder = JSONEncoder()
            let data = try encoder.encode(type)
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(WorkoutType.self, from: data)
            #expect(decoded == type)
        }
    }

    @Test
    func displayNameIsNotEmpty() {
        for type in WorkoutType.allCases {
            #expect(!type.displayName.isEmpty)
        }
    }

    @Test
    func iconIsValidSFSymbol() {
        for type in WorkoutType.allCases {
            #expect(!type.icon.isEmpty)
            #expect(type.icon.contains("figure"))
        }
    }
}
