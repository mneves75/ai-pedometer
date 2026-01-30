import Foundation

extension UserDefaults {
    static var shared: UserDefaults {
        UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    }

    @MainActor
    var sharedStepData: SharedStepData? {
        get {
            guard let data = data(forKey: AppConstants.UserDefaultsKeys.sharedStepData) else {
                return nil
            }
            do {
                return try JSONDecoder().decode(SharedStepData.self, from: data)
            } catch {
                Loggers.sync.error("shared_step_data_decode_failed", metadata: [
                    "error": error.localizedDescription
                ])
                return nil
            }
        }
        set {
            guard let newValue else {
                removeObject(forKey: AppConstants.UserDefaultsKeys.sharedStepData)
                return
            }
            do {
                let data = try JSONEncoder().encode(newValue)
                set(data, forKey: AppConstants.UserDefaultsKeys.sharedStepData)
            } catch {
                Loggers.sync.error("shared_step_data_encode_failed", metadata: [
                    "error": error.localizedDescription
                ])
            }
        }
    }
}
