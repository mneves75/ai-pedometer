import Foundation

struct TestUserDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = "AIPedometerTests.\(UUID().uuidString)"
        guard let suiteDefaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Failed to create UserDefaults suite '\(suiteName)'; refusing to fall back to .standard so tests never pollute real defaults")
        }
        defaults = suiteDefaults
        defaults.removePersistentDomain(forName: suiteName)
    }

    func reset() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
