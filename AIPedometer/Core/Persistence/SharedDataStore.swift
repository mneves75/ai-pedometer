import Foundation
import Observation

@Observable
@MainActor
final class SharedDataStore {
    private(set) var sharedData: SharedStepData?
    private let userDefaults: UserDefaults?

    init(userDefaults: UserDefaults? = .sharedAppGroup) {
        self.userDefaults = userDefaults
    }

    func refresh() {
        sharedData = userDefaults?.sharedStepData
    }

    func update(_ data: SharedStepData) {
        sharedData = data
        guard let userDefaults else {
            Loggers.sync.error("shared_step_data_write_skipped", metadata: [
                "reason": "app_group_unavailable"
            ])
            return
        }
        userDefaults.sharedStepData = data
    }
}
