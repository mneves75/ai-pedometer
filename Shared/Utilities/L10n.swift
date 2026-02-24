import Foundation

enum L10n {
    static func localized(
        _ key: String.LocalizationValue,
        table: String? = nil,
        bundle: Bundle = .main,
        locale: Locale? = nil,
        comment: StaticString? = nil
    ) -> String {
        let resolvedLanguageCode: String
        if let explicitLocale = locale {
            resolvedLanguageCode = AppLanguage.supportedLanguageCode(for: explicitLocale.identifier)
        } else {
            resolvedLanguageCode = AppLanguage.currentLanguageCode
        }
        let resolvedLocale = AppLanguage.locale(for: resolvedLanguageCode)
        let resolvedBundle = AppLanguage.localizationBundle(for: resolvedLanguageCode, bundle: bundle)
        return String(
            localized: key,
            table: table,
            bundle: resolvedBundle,
            locale: resolvedLocale,
            comment: comment
        )
    }
}
