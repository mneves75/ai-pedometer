import Foundation
import Testing

@testable import AIPedometer

struct BadgeTypeTests {
    @Test
    func localizedTitleIsNotEmpty() {
        for badge in BadgeType.allCases {
            #expect(!badge.localizedTitle.isEmpty)
        }
    }

    @Test
    func localizedDescriptionIsNotEmpty() {
        for badge in BadgeType.allCases {
            #expect(!badge.localizedDescription.isEmpty)
        }
    }

    @Test
    func allCasesHaveDistinctRawValues() {
        let rawValues = BadgeType.allCases.map(\.rawValue)
        let uniqueValues = Set(rawValues)
        #expect(rawValues.count == uniqueValues.count)
    }
}
