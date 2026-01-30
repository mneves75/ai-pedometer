import Foundation

enum AppLanguage {
    static func preferredLanguageCode(
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        if let bundleLanguage = bundle.preferredLocalizations.first, bundleLanguage != "Base" {
            return bundleLanguage
        }
        if let preferred = Locale.preferredLanguages.first {
            return preferred
        }
        return locale.identifier
    }

    static func displayName(
        for languageCode: String,
        locale: Locale = .current
    ) -> String {
        let normalized = languageCode.replacingOccurrences(of: "_", with: "-")
        if let name = locale.localizedString(forIdentifier: normalized) {
            return name
        }
        return locale.localizedString(forLanguageCode: normalized) ?? normalized
    }

    static func promptInstruction(
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        let code = preferredLanguageCode(bundle: bundle, locale: locale)
        return promptInstruction(languageCode: code, locale: locale)
    }

    static func promptInstruction(
        languageCode: String,
        locale: Locale = .current
    ) -> String {
        let name = displayName(for: languageCode, locale: locale)
        return "Respond in the user's app language: \(name) (\(languageCode))."
    }
}
