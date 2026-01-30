import Foundation
import Testing

@testable import AIPedometer

@MainActor
struct DemoModeStoreTests {
    @Test
    func initializesFakeDataFromUserDefaults() {
        let suiteName = "DemoModeStoreTests-" + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(Bool(false), "Failed to create UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: DemoModeKeys.useFakeData)

        let store = DemoModeStore(userDefaults: defaults)
        #expect(store.useFakeData)
    }

    @Test
    func persistsFakeDataChanges() {
        let suiteName = "DemoModeStoreTests-" + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(Bool(false), "Failed to create UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DemoModeStore(userDefaults: defaults)
        store.useFakeData = true

        #expect(defaults.bool(forKey: DemoModeKeys.useFakeData))
    }

    @Test
    func shouldUseFakeDataReturnsFalseByDefault() {
        let suiteName = "DemoModeStoreTests-" + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(Bool(false), "Failed to create UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DemoModeStore(userDefaults: defaults)
        #expect(!store.shouldUseFakeData)
    }

    @Test
    func shouldUseFakeDataReturnsTrueWhenEnabled() {
        let suiteName = "DemoModeStoreTests-" + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(Bool(false), "Failed to create UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DemoModeStore(userDefaults: defaults)
        store.useFakeData = true
        #expect(store.shouldUseFakeData)
    }
}
