import Foundation
import Observation

@Observable
@MainActor
final class SharedDataStore {
    private(set) var sharedData: SharedStepData?
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .shared) {
        self.userDefaults = userDefaults
    }

    func refresh() {
        sharedData = userDefaults.sharedStepData
    }

    func update(_ data: SharedStepData) {
        userDefaults.sharedStepData = data
        sharedData = data
    }
}
