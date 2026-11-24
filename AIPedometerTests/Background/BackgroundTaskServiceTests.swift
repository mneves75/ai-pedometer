import BackgroundTasks
import Foundation
import os
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

final class FakeAppRefreshTask: AppRefreshTaskProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storedHandler: (() -> Void)?
    private var storedCompleted: Bool?
    private let completionProbe = AppRefreshCompletionProbe()

    var expirationHandler: (() -> Void)? {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }

    var completed: Bool? {
        lock.withLock { storedCompleted }
    }

    func setTaskCompleted(success: Bool) {
        lock.withLock { storedCompleted = success }
        let completionProbe = completionProbe
        Task {
            await completionProbe.record(success)
        }
    }

    @MainActor
    func waitUntilCompleted() async -> Bool {
        await completionProbe.waitForCompletion()
    }
}

private actor AppRefreshCompletionProbe {
    private var result: Bool?
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    func record(_ result: Bool) {
        guard self.result == nil else { return }
        self.result = result
        let currentWaiters = waiters
        waiters.removeAll()
        for waiter in currentWaiters {
            waiter.resume(returning: result)
        }
    }

    func waitForCompletion() async -> Bool {
        if let result {
            return result
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

@MainActor
final class MockStepTrackingService: StepTrackingServiceProtocol {
    private(set) var refreshCalled = false
    private(set) var flushCallCount = 0

    func refreshTodayData() async {
        refreshCalled = true
    }

    func flushSharedData() {
        flushCallCount += 1
    }
}

@MainActor
final class BlockingStepTrackingService: StepTrackingServiceProtocol {
    private(set) var refreshStarted = false
    private(set) var cancellationObserved = false
    private(set) var committed = false
    private(set) var flushCallCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    func refreshTodayData() async {
        refreshStarted = true
        let currentStartWaiters = startWaiters
        startWaiters.removeAll()
        for waiter in currentStartWaiters {
            waiter.resume()
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelAndResume()
            }
        }
        guard !Task.isCancelled else { return }
        committed = true
    }

    func flushSharedData() {
        flushCallCount += 1
    }

    func waitUntilRefreshStarts() async {
        if refreshStarted {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilCancellationIsObserved() async {
        if cancellationObserved {
            return
        }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }

    private func cancelAndResume() {
        cancellationObserved = true
        let currentCancellationWaiters = cancellationWaiters
        cancellationWaiters.removeAll()
        for waiter in currentCancellationWaiters {
            waiter.resume()
        }
        continuation?.resume()
        continuation = nil
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
        #expect(scheduler.registeredIdentifiers == [AppConstants.BackgroundTaskIdentifiers.refresh])
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
        var reconciliationCount = 0
        let service = BackgroundTaskService(
            stepTrackingService: tracker,
            scheduler: scheduler,
            performHealthKitReconciliation: { reconciliationCount += 1 }
        )
        let task = FakeAppRefreshTask()

        service.handleAppRefresh(task: task)
        let completed = await task.waitUntilCompleted()

        #expect(completed)
        #expect(task.completed == true)
        #expect(tracker.refreshCalled == true)
        #expect(reconciliationCount == 1)
        #expect(tracker.flushCallCount == 1)
    }

    @Test("handleAppRefresh expiration from a background queue cancels refresh and does not get overwritten by late success")
    func handleAppRefreshExpirationWins() async {
        let scheduler = MockBackgroundScheduler()
        let tracker = BlockingStepTrackingService()
        var reconciliationCount = 0
        let service = BackgroundTaskService(
            stepTrackingService: tracker,
            scheduler: scheduler,
            performHealthKitReconciliation: { reconciliationCount += 1 }
        )
        let task = FakeAppRefreshTask()

        service.handleAppRefresh(task: task)
        await tracker.waitUntilRefreshStarts()
        DispatchQueue.global(qos: .utility).async {
            task.expirationHandler?()
        }
        await tracker.waitUntilCancellationIsObserved()
        let completed = await task.waitUntilCompleted()

        #expect(!completed)
        #expect(task.completed == false)
        #expect(tracker.cancellationObserved)
        #expect(!tracker.committed)
        #expect(reconciliationCount == 0)
        #expect(tracker.flushCallCount == 0)
    }

    @Test("handleAppRefresh does not overwrite completed success when expiration fires later")
    func handleAppRefreshDoesNotOverwriteCompletedSuccess() async {
        let scheduler = MockBackgroundScheduler()
        let tracker = MockStepTrackingService()
        let service = BackgroundTaskService(stepTrackingService: tracker, scheduler: scheduler)
        let task = FakeAppRefreshTask()

        service.handleAppRefresh(task: task)
        let completed = await task.waitUntilCompleted()
        task.expirationHandler?()

        #expect(completed)
        #expect(task.completed == true)
    }
}
