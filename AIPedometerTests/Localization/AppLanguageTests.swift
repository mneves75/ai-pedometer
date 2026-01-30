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

    @Test("Display name falls back to code for unknown language")
    func displayNameFallsBackToCode() {
        let name = AppLanguage.displayName(
            for: "xx-YY",
            locale: Locale(identifier: "en_US")
        )

        #expect(name == "xx-YY")
    }
}
