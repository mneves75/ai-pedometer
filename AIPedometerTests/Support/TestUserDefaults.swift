import Foundation

struct TestUserDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = "AIPedometerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
    }

    func reset() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
