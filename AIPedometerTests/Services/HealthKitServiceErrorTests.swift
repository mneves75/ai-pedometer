import Foundation
import HealthKit
import Testing

@testable import AIPedometer

@MainActor
struct HealthKitServiceErrorTests {
    @Test("Detects HealthKit no-data error")
    func detectsNoDataError() {
        let error = NSError(domain: HKErrorDomain, code: HKError.Code.errorNoData.rawValue)
        #expect(HealthKitService.isNoDataError(error))
    }

    @Test("Does not flag other HealthKit errors as no-data")
    func ignoresNonNoDataErrors() {
        let error = NSError(domain: HKErrorDomain, code: HKError.Code.errorAuthorizationDenied.rawValue)
        #expect(!HealthKitService.isNoDataError(error))
    }

    @Test("Does not flag non-HealthKit errors")
    func ignoresNonHealthKitErrors() {
        let error = NSError(domain: NSURLErrorDomain, code: URLError.cancelled.rawValue)
        #expect(!HealthKitService.isNoDataError(error))
    }
}
