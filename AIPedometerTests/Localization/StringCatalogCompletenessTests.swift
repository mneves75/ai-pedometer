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

    /// Scans production sources for localized string literals and requires each one to exist in the
    /// catalog.
    ///
    /// This is the direction the suite was missing. The catalog-side test above only checks entries that
    /// already exist, and `String(localized:)` silently returns the key itself when no entry is present —
    /// so a string could ship rendering English to pt-BR users while every localization test stayed green.
    /// That is exactly how 11 strings, five of them on the paywall, reached 0.95 untranslated.
    @Test("Every localized literal in the source has a catalog entry")
    func localizedLiteralsExistInCatalog() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let catalogURL = repoRoot
            .appendingPathComponent("Shared")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalogURL)) as? [String: Any]
        let strings = try #require(json?["strings"] as? [String: Any])
        let catalogKeys = Set(strings.keys)

        // Matches L10n.localized("…") and String(localized: "…") with a literal first argument.
        let pattern = #"(?:L10n\.localized\(\s*"((?:[^"\\]|\\.)*)"|String\(\s*localized:\s*"((?:[^"\\]|\\.)*)")"#
        let regex = try NSRegularExpression(pattern: pattern)

        var missing: [String] = []
        for target in ["AIPedometer", "Shared", "AIPedometerWatch", "AIPedometerWidgets"] {
            let targetRoot = repoRoot.appendingPathComponent(target)
            guard let walker = FileManager.default.enumerator(
                at: targetRoot,
                includingPropertiesForKeys: nil
            ) else { continue }

            for case let fileURL as URL in walker where fileURL.pathExtension == "swift" {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                let range = NSRange(source.startIndex..., in: source)
                for match in regex.matches(in: source, range: range) {
                    let captured = (1...2).lazy
                        .compactMap { Range(match.range(at: $0), in: source) }
                        .first
                    guard let captured else { continue }
                    // Escaped sequences in source (\" and \n) are literal characters in the catalog key.
                    let key = String(source[captured])
                        .replacingOccurrences(of: "\\\"", with: "\"")
                        .replacingOccurrences(of: "\\n", with: "\n")
                    if !catalogKeys.contains(key) {
                        missing.append("\(fileURL.lastPathComponent): \(key)")
                    }
                }
            }
        }

        let report = missing.sorted().joined(separator: " | ")
        #expect(
            missing.isEmpty,
            "Localized literals with no catalog entry (they render in English on pt-BR devices): \(report)"
        )
    }
}
