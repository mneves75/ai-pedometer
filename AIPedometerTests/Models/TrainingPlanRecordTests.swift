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
