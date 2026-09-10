import Foundation

enum AppLanguage {
    static let englishCode = "en"
    static let portugueseBrazilCode = "pt-BR"
    static let englishLocaleIdentifier = "en-US"

    static var currentLanguageCode: String {
        defaultLanguageCode
    }

    /// Language resolution for the default path (`Locale.preferredLanguages`, `.main` bundle),
    /// resolved once per process.
    ///
    /// `L10n.localized` previously re-derived this for every localized string: once via
    /// `currentLanguageCode`, again in `locale(for:)` and a third time in
    /// `localizationBundle(for:bundle:)`, so `supportedLanguageCode` — which builds a `Locale`
    /// and reads its language and region — ran three times per call across 612 call sites.
    /// iOS requires an app relaunch to change the app language, and `AIPedometerApp` already
    /// snapshots `appLocale` once at init, so resolving once matches the shipped model.
    /// Callers that pass an explicit `locale:` or a non-`.main` bundle still resolve normally.
    static let defaultLanguageCode: String = resolvedLanguageCode()

    static let defaultLocale: Locale = locale(for: defaultLanguageCode)

    /// The `.main`-bundle localization bundle for `defaultLanguageCode`, resolved once.
    ///
    /// This is the most expensive third of the old per-string work: `localizationBundle(for:bundle:)`
    /// re-ran `supportedLanguageCode` *and* did a `Bundle.path(forResource:ofType:)` lookup plus a
    /// `Bundle(path:)` construction on every localized string. Only the `.main` case is cached;
    /// callers passing a different bundle (tests loading `pt-BR.lproj` explicitly) resolve normally.
    static let defaultLocalizationBundle: Bundle = localizationBundle(for: defaultLanguageCode)

    static var currentLocale: Locale {
        defaultLocale
    }

    static func resolvedLanguageCode(
        preferredLanguages: [String] = Locale.preferredLanguages,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        if let preferred = preferredLanguages.first {
            return supportedLanguageCode(for: preferred)
        }
        if let bundleLanguage = bundle.preferredLocalizations.first, bundleLanguage != "Base" {
            return supportedLanguageCode(for: bundleLanguage)
        }
        return supportedLanguageCode(for: locale.identifier)
    }

    static func supportedLanguageCode(for languageCode: String) -> String {
        let normalized = languageCode.replacingOccurrences(of: "_", with: "-")
        let locale = Locale(identifier: normalized)
        let language = locale.language.languageCode?.identifier.lowercased()
        let region = locale.language.region?.identifier.uppercased()

        if language == "pt", region == "BR" {
            return portugueseBrazilCode
        }
        return englishCode
    }

    static func locale(for languageCode: String) -> Locale {
        if supportedLanguageCode(for: languageCode) == portugueseBrazilCode {
            return Locale(identifier: portugueseBrazilCode)
        }
        return Locale(identifier: englishLocaleIdentifier)
    }

    static func localizationBundle(
        for languageCode: String,
        bundle: Bundle = .main
    ) -> Bundle {
        let resolvedCode = supportedLanguageCode(for: languageCode)
        if let path = bundle.path(forResource: resolvedCode, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            return localizedBundle
        }
        if let englishPath = bundle.path(forResource: englishCode, ofType: "lproj"),
           let englishBundle = Bundle(path: englishPath) {
            return englishBundle
        }
        return bundle
    }

    static func displayName(
        for languageCode: String,
        locale: Locale = .current
    ) -> String {
        let normalized = supportedLanguageCode(for: languageCode)
        if let name = locale.localizedString(forIdentifier: normalized) {
            return name
        }
        return locale.localizedString(forLanguageCode: normalized) ?? normalized
    }

    static func promptInstruction(
        preferredLanguages: [String] = Locale.preferredLanguages,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        let code = resolvedLanguageCode(
            preferredLanguages: preferredLanguages,
            bundle: bundle,
            locale: locale
        )
        return promptInstruction(languageCode: code, locale: locale)
    }

    static func promptInstruction(
        languageCode: String,
        locale: Locale = .current
    ) -> String {
        let code = supportedLanguageCode(for: languageCode)
        let name = displayName(for: code, locale: locale)
        return "Respond in the user's app language: \(name) (\(code))."
    }
}
