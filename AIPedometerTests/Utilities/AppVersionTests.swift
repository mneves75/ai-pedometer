import Testing

@testable import AIPedometer

struct AppVersionTests {
    @Test
    func usesInfoDictionaryValuesWhenPresent() {
        let info: [String: Any] = [
            "CFBundleShortVersionString": "2.3.4",
            "CFBundleVersion": "42"
        ]
        let version = AppVersion(info: info)
        #expect(version.shortVersion == "2.3.4")
        #expect(version.build == "42")
        #expect(version.display == "2.3.4 (42)")
    }

    @Test
    func fallsBackToZeroWhenMissing() {
        let version = AppVersion(info: [:])
        #expect(version.shortVersion == "0")
        #expect(version.build == "0")
        #expect(version.display == "0 (0)")
    }
}
