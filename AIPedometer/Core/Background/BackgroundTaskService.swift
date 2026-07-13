#if os(iOS)
import BackgroundTasks
import Foundation

protocol BackgroundTaskScheduling: AnyObject {
    func register(
        forTaskWithIdentifier identifier: String,
        handler: @escaping @Sendable (BGTask) -> Void
    )
    func submit(_ request: BGTaskRequest) throws
}

final class BGTaskSchedulerAdapter: BackgroundTaskScheduling {
    func register(
        forTaskWithIdentifier identifier: String,
        handler: @escaping @Sendable (BGTask) -> Void
    ) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handler(task)
        }
    }

    func submit(_ request: BGTaskRequest) throws {
        try BGTaskScheduler.shared.submit(request)
    }
}

protocol BackgroundTaskProtocol: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

protocol AppRefreshTaskProtocol: BackgroundTaskProtocol {}

private final class TaskCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false

    func complete(_ task: any BackgroundTaskProtocol, success: Bool) {
        lock.lock()
        let shouldComplete = !didComplete
        if shouldComplete {
            didComplete = true
        }
        lock.unlock()

        guard shouldComplete else { return }
        task.setTaskCompleted(success: success)
    }
}

/// BGTask callbacks are delivered by the system and completion/expiration callbacks are thread-safe APIs.
/// Safety invariant: tasks are only mutated through documented completion/expiration APIs.
extension BGTask: BackgroundTaskProtocol, @retroactive @unchecked Sendable {}
extension BGAppRefreshTask: AppRefreshTaskProtocol {}

@MainActor
final class BackgroundTaskService {
    private let stepTrackingService: any StepTrackingServiceProtocol
    private let scheduler: any BackgroundTaskScheduling
    private let performHealthKitReconciliation: @MainActor @Sendable () async -> Void
    private var didRegisterTasks = false

    init(
        stepTrackingService: any StepTrackingServiceProtocol,
        scheduler: any BackgroundTaskScheduling = BGTaskSchedulerAdapter(),
        performHealthKitReconciliation: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.stepTrackingService = stepTrackingService
        self.scheduler = scheduler
        self.performHealthKitReconciliation = performHealthKitReconciliation
    }

    func registerTasks() {
        guard !didRegisterTasks else { return }
        didRegisterTasks = true
        scheduler.register(forTaskWithIdentifier: AppConstants.BackgroundTaskIdentifiers.refresh) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                Loggers.background.error("background.refresh_task_cast_failed")
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                self.handleAppRefresh(task: refreshTask)
            }
        }

    }

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: AppConstants.BackgroundTaskIdentifiers.refresh)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try scheduler.submit(request)
        } catch {
            Loggers.background.error("background.schedule_failed", metadata: ["error": String(describing: error)])
        }
    }

    func handleAppRefresh(task: any AppRefreshTaskProtocol) {
        scheduleAppRefresh()
        let completionGate = TaskCompletionGate()
        let operation = Task { @MainActor in
            await performRefresh()
            guard !Task.isCancelled else { return }
            completionGate.complete(task, success: true)
        }
        task.expirationHandler = {
            operation.cancel()
            completionGate.complete(task, success: false)
        }
    }

    @MainActor
    func performRefresh() async {
        defer { stepTrackingService.flushSharedData() }
        await stepTrackingService.refreshTodayData()
        guard !Task.isCancelled else { return }
        await performHealthKitReconciliation()
    }
}
#endif
