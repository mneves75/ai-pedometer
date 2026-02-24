import Foundation
import Observation

struct WorkoutSummary: Equatable, Sendable {
    let type: WorkoutType
    let startTime: Date
    let endTime: Date
    let steps: Int
    let distance: Double
    let activeCalories: Double
}

enum WorkoutState: Equatable, Sendable {
    case idle
    case preparing
    case active
    case paused
    case completed(summary: WorkoutSummary)
    case failed(error: WorkoutError)
}

enum WorkoutEvent: Sendable {
    case start
    case prepared
    case pause
    case resume
    case finish(summary: WorkoutSummary)
    case discard
    case error(WorkoutError)
}

@Observable
@MainActor
final class WorkoutStateMachine {
    private(set) var state: WorkoutState = .idle

    func send(_ event: WorkoutEvent) {
        state = nextState(for: event)
    }

    private func nextState(for event: WorkoutEvent) -> WorkoutState {
        switch (state, event) {
        case (.idle, .start):
            return .preparing
        case (.preparing, .prepared):
            return .active
        case (.preparing, .error(let error)):
            return .failed(error: error)
        case (.preparing, .discard):
            return .idle
        case (.preparing, .finish(let summary)):
            return .completed(summary: summary)
        case (.active, .pause):
            return .paused
        case (.paused, .resume):
            return .active
        case (.active, .finish(let summary)), (.paused, .finish(let summary)):
            return .completed(summary: summary)
        case (.active, .discard), (.paused, .discard):
            return .idle
        case (.active, .error(let error)), (.paused, .error(let error)):
            return .failed(error: error)
        default:
            return state
        }
    }
}
