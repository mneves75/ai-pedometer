import Foundation
import SwiftData

@Model
final class TrainingPlanRecord {
    var id: UUID = UUID()
    var name: String = ""
    var planDescription: String = ""
    var startDate: Date = Date.now
    var endDate: Date?
    var weeklyTargetsJSON: Data = Data()
    var status: String = PlanStatus.active.rawValue
    var primaryGoal: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    
    enum PlanStatus: String, Codable, Sendable {
        case active
        case completed
        case paused
        case abandoned
    }
    
    init() {}
    
    var planStatus: PlanStatus {
        get { PlanStatus(rawValue: status) ?? .active }
        set { status = newValue.rawValue }
    }
    
    var weeklyTargets: [WeeklyTarget] {
        get {
            guard !weeklyTargetsJSON.isEmpty else { return [] }
            do {
                return try JSONDecoder().decode([WeeklyTarget].self, from: weeklyTargetsJSON)
            } catch {
                Loggers.ai.error("ai.training_plan_weekly_targets_decode_failed", metadata: [
                    "error": error.localizedDescription
                ])
                return []
            }
        }
        set {
            do {
                weeklyTargetsJSON = try JSONEncoder().encode(newValue)
            } catch {
                Loggers.ai.error("ai.training_plan_weekly_targets_encode_failed", metadata: [
                    "error": error.localizedDescription
                ])
            }
        }
    }
    
    var isActive: Bool {
        planStatus == .active && deletedAt == nil
    }
    
    var progressPercentage: Double {
        guard let startDate = Optional(startDate),
              let endDate = endDate ?? Calendar.current.date(byAdding: .weekOfYear, value: weeklyTargets.count, to: startDate) else {
            return 0
        }
        
        let totalDuration = endDate.timeIntervalSince(startDate)
        let elapsed = Date().timeIntervalSince(startDate)
        
        guard totalDuration > 0 else { return 0 }
        return min(max(elapsed / totalDuration, 0), 1)
    }
    
    var currentWeek: Int {
        currentWeek(on: .now)
    }

    func currentWeek(on date: Date, calendar: Calendar = .current) -> Int {
        let startDay = calendar.startOfDay(for: startDate)
        let currentDay = calendar.startOfDay(for: date)
        let daysElapsed = max(calendar.dateComponents([.day], from: startDay, to: currentDay).day ?? 0, 0)
        let weekIndex = daysElapsed / 7
        let week = weekIndex + 1
        return min(max(week, 1), weeklyTargets.count)
    }
    
    var currentWeekTarget: WeeklyTarget? {
        let index = currentWeek - 1
        guard index >= 0, index < weeklyTargets.count else { return nil }
        return weeklyTargets[index]
    }
}

extension TrainingPlanRecord.PlanStatus {
    var localizedName: String {
        switch self {
        case .active:
            return String(localized: "Active", comment: "Training plan status label")
        case .completed:
            return String(localized: "Completed", comment: "Training plan status label")
        case .paused:
            return String(localized: "Paused", comment: "Training plan status label")
        case .abandoned:
            return String(localized: "Abandoned", comment: "Training plan status label")
        }
    }
}
