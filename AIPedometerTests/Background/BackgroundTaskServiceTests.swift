import BackgroundTasks
import Foundation
import Testing

@testable import AIPedometer

final class MockBackgroundScheduler: BackgroundTaskScheduling {
    private(set) var registeredIdentifiers: [String] = []
    private(set) var submittedRequests: [BGTaskRequest] = []
    private(set) var handlers: [String: @Sendable (BGTask) -> Void] = [:]

    func register(forTaskWithIdentifier identifier: String, handler: @escaping @Sendable (BGTask) -> Void) {
        registeredIdentifiers.append(identifier)
        handlers[identifier] = handler
    }

    func submit(_ request: BGTaskRequest) throws {
        submittedRequests.append(request)
    }
}

final class FakeAppRefreshTask: AppRefreshTaskProtocol {
    var expirationHandler: (() -> Void)?
    private(set) var completed: Bool?

    func setTaskCompleted(success: Bool) {
        completed = success
    }
}

final class FakeProcessingTask: ProcessingTaskProtocol {
    var expirationHandler: (() -> Void)?
    private(set) var completed: Bool?

    func setTaskCompleted(success: Bool) {
        completed = success
    }
}

@MainActor
final class MockStepTrackingService: StepTrackingServiceProtocol {
    private(set) var refreshCalled = false
    var refreshDelayNanoseconds: UInt64 = 0

    func refreshTodayData() async {
        if refreshDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: refreshDelayNanoseconds)
        }
        refreshCalled = true
    }
}

@MainActor
struct BackgroundTaskServiceTests {
    @Test("registerTasks registers identifiers")
    func registerTasksRegistersIdentifiers() {
        let scheduler = MockBackgroundScheduler()
        let service = BackgroundTaskService(
            stepTrackingService: MockStepTrackingService(),
            scheduler: scheduler
        )

        service.registerTasks()

        #expect(scheduler.registeredIdentifiers.contains(AppConstants.BackgroundTaskIdentifiers.refresh))
        #expect(scheduler.registeredIdentifiers.contains(AppConstants.BackgroundTaskIdentifiers.processing))
    }

    @Test("scheduleAppRefresh submits a refresh request")
    func scheduleAppRefreshSubmitsRequest() {
        let scheduler = MockBackgroundScheduler()
        let service = BackgroundTaskService(
            stepTrackingService: MockStepTrackingService(),
            scheduler: scheduler
        )

        service.scheduleAppRefresh()

        #expect(scheduler.submittedRequests.count == 1)
        #expect(scheduler.submittedRequests.first is BGAppRefreshTaskRequest)
    }

    @Test("handleAppRefresh completes task and triggers refresh")
    func handleAppRefreshCompletesTask() async {
        let scheduler = MockBackgroundScheduler()
        let tracker = MockStepTrackingService()
        let service = BackgroundTaskService(stepTrackingService: tracker, scheduler: scheduler)
        let task = FakeAppRefreshTask()

        service.handleAppRefresh(task: task)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(task.completed == true)
        #expect(tracker.refreshCalled == true)
    }

    @Test("handleAppRefresh expiration does not get overwritten by late success")
    func handleAppRefreshExpirationWins() async {
        let scheduler = MockBackgroundScheduler()
        let tracker = MockStepTrackingService()
        tracker.refreshDelayNanoseconds = 80_000_000
        let service = BackgroundTaskService(stepTrackingService: tracker, scheduler: scheduler)
        let task = FakeAppRefreshTask()

        service.handleAppRefresh(task: task)
        task.expirationHandler?()
        try? await Task.sleep(nanoseconds: 120_000_000)

        #expect(task.completed == false)
    }

    @Test("handleProcessing marks task complete")
    func handleProcessingCompletesTask() async {
        let scheduler = MockBackgroundScheduler()
        let tracker = MockStepTrackingService()
        let service = BackgroundTaskService(stepTrackingService: tracker, scheduler: scheduler)
        let task = FakeProcessingTask()

        service.handleProcessing(task: task)
        try? await Task.sleep(nanoseconds: 10_000_000)

        #expect(task.completed == true)
    }
}
