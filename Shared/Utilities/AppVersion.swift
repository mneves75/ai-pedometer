import Foundation

struct AppVersion: Sendable, Equatable {
    let shortVersion: String
    let build: String

    init(bundle: Bundle = .main) {
        self.init(info: bundle.infoDictionary ?? [:])
    }

    init(info: [String: Any]) {
        shortVersion = info["CFBundleShortVersionString"] as? String ?? "0"
        build = info["CFBundleVersion"] as? String ?? "0"
    }

    var display: String {
        "\(shortVersion) (\(build))"
    }
}
