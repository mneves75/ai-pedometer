import Foundation
import Testing
@testable import AIPedometer

@Suite("Pluralization Tests")
@MainActor
struct PluralTests {

    // MARK: - Plural Variations

    @Test(
        "Imported route waypoint count uses plural variations",
        arguments: [
            (1, "en", "1 waypoint"),
            (2, "en", "2 waypoints"),
            (1, "pt-BR", "1 ponto de referência"),
            (2, "pt-BR", "2 pontos de referência")
        ]
    )
    func waypointCountPluralizes(count: Int, language: String, expected: String) {
        let text = WorkoutsView.waypointCountText(count, locale: Locale(identifier: language))
        #expect(text == expected)
    }

    @Test(
        "Shared streak text used by the watch and widgets pluralizes",
        arguments: [
            (1, "en", "1 day"),
            (2, "en", "2 days"),
            (1, "pt-BR", "1 dia"),
            (2, "pt-BR", "2 dias")
        ]
    )
    func sharedStreakTextPluralizes(days: Int, language: String, expected: String) {
        #expect(Localization.streakDays(days, locale: Locale(identifier: language)) == expected)
    }

    // The widget composed "Streak %lld days" through `Localization.format`, which ignores plural
    // variations and rendered "Streak 1 days". These pin the strings the widget actually shows.
    @Test(
        "Weekly widget streak label pluralizes",
        arguments: [
            (1, "en", "Streak: 1 day"),
            (2, "en", "Streak: 2 days"),
            (1, "pt-BR", "Sequência: 1 dia"),
            (2, "pt-BR", "Sequência: 2 dias")
        ]
    )
    func widgetStreakLabelPluralizes(days: Int, language: String, expected: String) {
        #expect(Localization.widgetStreakLabel(days, locale: Locale(identifier: language)) == expected)
    }

    @Test(
        "Weekly widget accessibility summary pluralizes the streak",
        arguments: [
            (false, "en", "8 steps today, 40 steps this week, streak of 1 day"),
            (true, "en", "8 pushes today, 40 pushes this week, streak of 1 day"),
            (false, "pt-BR", "8 passos hoje, 40 passos nesta semana, sequência de 1 dia"),
            (true, "pt-BR", "8 impulsos hoje, 40 impulsos nesta semana, sequência de 1 dia")
        ]
    )
    func widgetWeeklySummaryPluralizes(isWheelchair: Bool, language: String, expected: String) {
        let summary = Localization.widgetWeeklySummary(
            today: "8",
            week: "40",
            streakDays: 1,
            isWheelchair: isWheelchair,
            locale: Locale(identifier: language)
        )
        #expect(summary == expected)
    }
}
