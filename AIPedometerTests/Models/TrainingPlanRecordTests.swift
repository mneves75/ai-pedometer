import Foundation
import Testing

@testable import AIPedometer

@MainActor
struct TrainingPlanRecordTests {
    @Test("currentWeek uses 7-day windows from the start date")
    func currentWeekUsesSevenDayWindows() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let record = makeRecord(startDate: startDate, weeks: 4)

        let threeDaysLater = calendar.date(byAdding: .day, value: 3, to: startDate) ?? startDate
        #expect(record.currentWeek(on: threeDaysLater, calendar: calendar) == 1)

        let eightDaysLater = calendar.date(byAdding: .day, value: 8, to: startDate) ?? startDate
        #expect(record.currentWeek(on: eightDaysLater, calendar: calendar) == 2)
    }

    @Test("currentWeek clamps to available targets")
    func currentWeekClampsToAvailableTargets() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let record = makeRecord(startDate: startDate, weeks: 4)

        let thirtyDaysLater = calendar.date(byAdding: .day, value: 30, to: startDate) ?? startDate
        #expect(record.currentWeek(on: thirtyDaysLater, calendar: calendar) == 4)
    }

    @Test("currentWeek returns 0 when no weekly targets exist")
    func currentWeekReturnsZeroWithoutTargets() {
        let record = makeRecord(startDate: Date(timeIntervalSince1970: 1_700_000_000), weeks: 0)
        #expect(record.currentWeek == 0)
    }

    @Test("invalid status does not remain active")
    func invalidStatusDoesNotRemainActive() {
        let record = makeRecord(startDate: Date(timeIntervalSince1970: 1_700_000_000), weeks: 2)
        record.status = "broken"

        #expect(record.planStatus == .abandoned)
        #expect(!record.isActive)
    }

    @Test("invalid weekly target payload is treated as inactive")
    func invalidWeeklyTargetsPayloadIsInactive() {
        let record = makeRecord(startDate: Date(timeIntervalSince1970: 1_700_000_000), weeks: 2)
        record.weeklyTargetsJSON = Data("invalid".utf8)

        #expect(record.weeklyTargets.isEmpty)
        #expect(!record.hasValidPlanData)
        #expect(!record.isActive)
    }

    @Test("current workout recommendation uses the active weekly target")
    func currentWorkoutRecommendationUsesActiveWeeklyTarget() {
        let record = makeRecord(startDate: Date(timeIntervalSince1970: 1_700_000_000), weeks: 1)
        record.planDescription = "Build toward a stronger routine"
        record.primaryGoal = TrainingGoalType.reach10k.rawValue
        record.weeklyTargets = [
            WeeklyTarget(
                weekNumber: 1,
                dailyStepTarget: 9_000,
                activeDaysRequired: 5,
                focusTip: "Keep your route steady"
            )
        ]

        let recommendation = record.currentWorkoutRecommendation

        #expect(recommendation?.intent == .build)
        #expect(recommendation?.difficulty == 4)
        #expect(recommendation?.rationale == "Build toward a stronger routine")
        #expect(recommendation?.targetSteps == 9_000)
        #expect(recommendation?.estimatedMinutes == 81)
        #expect(recommendation?.suggestedTimeOfDay == .anytime)
        #expect(record.currentWorkoutRecommendationSummary == "Keep your route steady")
    }

    @Test("current workout recommendation falls back safely when plan data is incomplete")
    func currentWorkoutRecommendationFallsBackSafely() {
        let emptyRecord = makeRecord(startDate: Date(timeIntervalSince1970: 1_700_000_000), weeks: 0)
        emptyRecord.planDescription = "No current target yet"

        #expect(emptyRecord.currentWorkoutRecommendation == nil)
        #expect(emptyRecord.currentWorkoutRecommendationSummary == "No current target yet")

        let unknownGoalRecord = makeRecord(startDate: Date(timeIntervalSince1970: 1_700_000_000), weeks: 1)
        unknownGoalRecord.primaryGoal = "unknown"

        #expect(unknownGoalRecord.currentWorkoutRecommendation?.intent == .maintain)
    }

    private func makeRecord(startDate: Date, weeks: Int) -> TrainingPlanRecord {
        let record = TrainingPlanRecord()
        record.startDate = startDate
        if weeks > 0 {
            record.weeklyTargets = (1...weeks).map { index in
                WeeklyTarget(
                    weekNumber: index,
                    dailyStepTarget: 6000,
                    activeDaysRequired: 5,
                    focusTip: "Focus on consistency"
                )
            }
        } else {
            record.weeklyTargets = []
        }
        return record
    }
}
