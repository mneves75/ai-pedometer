import Foundation
import Testing

@testable import AIPedometer

@MainActor
struct WorkoutStateMachineTests {
    @Test
    func initialStateIsIdle() {
        let machine = WorkoutStateMachine()
        #expect(machine.state == .idle)
    }

    @Test
    func startTransitionsToPreparing() {
        let machine = WorkoutStateMachine()
        machine.send(.start)
        #expect(machine.state == .preparing)
    }

    @Test
    func preparedTransitionsToActive() {
        let machine = WorkoutStateMachine()
        machine.send(.start)
        machine.send(.prepared)

        #expect(machine.state == .active)
    }

    @Test
    func pauseFromActiveTransitionsToPaused() {
        let machine = WorkoutStateMachine()
        machine.send(.start)
        machine.send(.prepared)
        machine.send(.pause)

        guard case .paused = machine.state else {
            Issue.record("Expected paused state")
            return
        }
    }

    @Test
    func resumeFromPausedTransitionsToActive() {
        let machine = WorkoutStateMachine()
        machine.send(.start)
        machine.send(.prepared)
        machine.send(.pause)
        machine.send(.resume)

        #expect(machine.state == .active)
    }

    @Test
    func finishFromActiveTransitionsToCompleted() {
        let machine = WorkoutStateMachine()
        machine.send(.start)
        machine.send(.prepared)

        let summary = WorkoutSummary(
            type: .indoorRun,
            startTime: .now,
            endTime: .now,
            steps: 5_000,
            distance: 4.2,
            activeCalories: 320
        )
        machine.send(.finish(summary: summary))

        if case .completed(let result) = machine.state {
            #expect(result.steps == 5_000)
            #expect(result.type == .indoorRun)
        } else {
            Issue.record("Expected completed state")
        }
    }

    @Test
    func discardFromActiveTransitionsToIdle() {
        let machine = WorkoutStateMachine()
        machine.send(.start)
        machine.send(.prepared)
        machine.send(.discard)
        #expect(machine.state == .idle)
    }

    @Test
    func discardFromPreparingTransitionsToIdle() {
        let machine = WorkoutStateMachine()
        machine.send(.start)
        machine.send(.discard)
        #expect(machine.state == .idle)
    }

    @Test
    func finishFromPreparingTransitionsToCompleted() {
        let machine = WorkoutStateMachine()
        machine.send(.start)

        let summary = WorkoutSummary(
            type: .outdoorWalk,
            startTime: .now,
            endTime: .now,
            steps: 0,
            distance: 0,
            activeCalories: 0
        )
        machine.send(.finish(summary: summary))

        guard case .completed = machine.state else {
            Issue.record("Expected completed state from preparing finish")
            return
        }
    }

    @Test
    func errorFromPreparingTransitionsToFailed() {
        let machine = WorkoutStateMachine()
        machine.send(.start)
        machine.send(.error(.notAuthorized))

        if case .failed(let error) = machine.state {
            #expect(error == .notAuthorized)
        } else {
            Issue.record("Expected failed state")
        }
    }

    @Test
    func invalidTransitionDoesNotChangeState() {
        let machine = WorkoutStateMachine()
        machine.send(.pause)
        #expect(machine.state == .idle)
    }
}
