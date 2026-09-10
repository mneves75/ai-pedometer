import Foundation

enum L10n {
    static func localized(
        _ key: String.LocalizationValue,
        table: String? = nil,
        bundle: Bundle = .main,
        locale: Locale? = nil,
        comment: StaticString? = nil
    ) -> String {
        let resolvedLocale: Locale
        let resolvedBundle: Bundle
        if locale == nil, bundle === Bundle.main {
            // Default path — the overwhelming majority of the 600+ call sites. Language code,
            // locale and localization bundle are all resolved once per process.
            // See `AppLanguage.defaultLanguageCode`.
            resolvedLocale = AppLanguage.defaultLocale
            resolvedBundle = AppLanguage.defaultLocalizationBundle
        } else {
            let resolvedLanguageCode = locale.map { AppLanguage.supportedLanguageCode(for: $0.identifier) }
                ?? AppLanguage.defaultLanguageCode
            resolvedLocale = AppLanguage.locale(for: resolvedLanguageCode)
            resolvedBundle = AppLanguage.localizationBundle(for: resolvedLanguageCode, bundle: bundle)
        }
        return String(
            localized: key,
            table: table,
            bundle: resolvedBundle,
            locale: resolvedLocale,
            comment: comment
        )
    }
}
