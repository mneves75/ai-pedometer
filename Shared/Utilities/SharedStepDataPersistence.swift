import Foundation

enum SharedStepDataPersistence {
    static func load(from userDefaults: UserDefaults?) -> SharedStepData? {
        guard let userDefaults,
              let data = userDefaults.data(forKey: AppConstants.UserDefaultsKeys.sharedStepData) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(SharedStepData.self, from: data)
        } catch {
            Loggers.sync.error("shared_step_data_decode_failed", metadata: [
                "error": error.localizedDescription
            ])
            userDefaults.removeObject(forKey: AppConstants.UserDefaultsKeys.sharedStepData)
            return nil
        }
    }

    static func save(_ value: SharedStepData?, to userDefaults: UserDefaults) {
        guard let value else {
            userDefaults.removeObject(forKey: AppConstants.UserDefaultsKeys.sharedStepData)
            return
        }

        do {
            let state = Signposts.sync.begin("SharedStepDataEncode")
            defer { Signposts.sync.end("SharedStepDataEncode", state) }
            let data = try JSONEncoder().encode(value)
            userDefaults.set(data, forKey: AppConstants.UserDefaultsKeys.sharedStepData)
        } catch {
            Loggers.sync.error("shared_step_data_encode_failed", metadata: [
                "error": error.localizedDescription
            ])
        }
    }
}
