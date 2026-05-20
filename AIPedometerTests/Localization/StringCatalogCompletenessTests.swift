import Foundation
import Testing

@Suite("String catalog completeness")
struct StringCatalogCompletenessTests {
    @Test("Shared app strings have English and Brazilian Portuguese values")
    func sharedStringsHaveRequiredLocalizations() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = repoRoot
            .appendingPathComponent("Shared")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Localizable.xcstrings")

        let data = try Data(contentsOf: catalogURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try #require(json?["strings"] as? [String: Any])

        var missing: [String] = []
        for key in strings.keys.sorted() {
            let entry = strings[key] as? [String: Any]
            let localizations = entry?["localizations"] as? [String: Any]
            for locale in ["en", "pt-BR"] {
                let localeEntry = localizations?[locale] as? [String: Any]
                let stringUnit = localeEntry?["stringUnit"] as? [String: Any]
                let value = stringUnit?["value"] as? String
                if value?.isEmpty != false {
                    missing.append("\(key) [\(locale)]")
                }
            }
        }

        #expect(missing.isEmpty, "Missing required localizations: \(missing.joined(separator: ", "))")
    }
}
