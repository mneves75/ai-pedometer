import Foundation

extension UserDefaults {
    static var sharedAppGroup: UserDefaults? {
        UserDefaults(suiteName: AppConstants.appGroupID)
    }

    @MainActor
    var sharedStepData: SharedStepData? {
        get { SharedStepDataPersistence.load(from: self) }
        set {
            SharedStepDataPersistence.save(newValue, to: self)
        }
    }
}
