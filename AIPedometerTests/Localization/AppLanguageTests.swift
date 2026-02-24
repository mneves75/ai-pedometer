import Foundation
import Testing

@testable import AIPedometer

@Suite("AppLanguage Tests")
struct AppLanguageTests {
    @Test("Prompt instruction includes language code")
    func promptInstructionIncludesLanguageCode() {
        let instruction = AppLanguage.promptInstruction(
            languageCode: "pt-BR",
            locale: Locale(identifier: "en_US")
        )

        #expect(instruction.contains("Respond in the user's app language"))
        #expect(instruction.contains("pt-BR"))
    }

    @Test("Display name falls back to English for unsupported language")
    func displayNameFallsBackToEnglish() {
        let name = AppLanguage.displayName(
            for: "xx-YY",
            locale: Locale(identifier: "en_US")
        )

        #expect(name == "English")
    }

    @Test("Strict language policy allows only pt-BR and defaults to en")
    func strictLanguagePolicy() {
        #expect(AppLanguage.supportedLanguageCode(for: "pt-BR") == "pt-BR")
        #expect(AppLanguage.supportedLanguageCode(for: "pt_BR") == "pt-BR")
        #expect(AppLanguage.supportedLanguageCode(for: "pt-BR-u-hc-h23") == "pt-BR")
        #expect(AppLanguage.supportedLanguageCode(for: "pt-PT") == "en")
        #expect(AppLanguage.supportedLanguageCode(for: "pt") == "en")
        #expect(AppLanguage.supportedLanguageCode(for: "en-US") == "en")
        #expect(AppLanguage.supportedLanguageCode(for: "fr-FR") == "en")
    }

    @Test("Resolved language follows strict first-preference policy")
    func resolvedLanguageUsesStrictFirstPreference() {
        let fallbackToEnglish = AppLanguage.resolvedLanguageCode(
            preferredLanguages: ["pt-PT", "pt-BR"]
        )
        #expect(fallbackToEnglish == "en")

        let portugueseBrazil = AppLanguage.resolvedLanguageCode(
            preferredLanguages: ["pt-BR", "en-US"]
        )
        #expect(portugueseBrazil == "pt-BR")
    }

    @Test("Resolved locale is deterministic for supported languages")
    func localeResolutionIsDeterministic() {
        #expect(AppLanguage.supportedLanguageCode(for: AppLanguage.locale(for: "pt-BR").identifier) == "pt-BR")
        #expect(AppLanguage.supportedLanguageCode(for: AppLanguage.locale(for: "en-US").identifier) == "en")
        #expect(AppLanguage.supportedLanguageCode(for: AppLanguage.locale(for: "fr-FR").identifier) == "en")
    }

    @Test("L10n resolves strings for explicit locale overrides")
    func l10nResolvesExplicitLocaleOverrides() {
        let portuguese = L10n.localized("Workouts", locale: Locale(identifier: "pt-BR"))
        let english = L10n.localized("Workouts", locale: Locale(identifier: "en-US"))

        #expect(portuguese == "Treinos")
        #expect(english == "Workouts")
    }
}
