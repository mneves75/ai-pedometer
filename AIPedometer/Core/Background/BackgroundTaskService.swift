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
protocol ProcessingTaskProtocol: BackgroundTaskProtocol {}

extension BGTask: BackgroundTaskProtocol {}
extension BGAppRefreshTask: AppRefreshTaskProtocol {}
extension BGProcessingTask: ProcessingTaskProtocol {}

/// BGTask types are reference-based and thread-safe for completion/expiration callbacks.
/// Safety invariant: the boxed task reference is only used on the MainActor after registration.
/// TODO: Remove @unchecked Sendable when BackgroundTasks adopts Sendable or when isolation can avoid crossings.
private struct BackgroundTaskBox<TaskType: BackgroundTaskProtocol>: @unchecked Sendable {
    let task: TaskType
}

@MainActor
final class BackgroundTaskService {
    private let stepTrackingService: any StepTrackingServiceProtocol
    private let scheduler: any BackgroundTaskScheduling

    init(
        stepTrackingService: any StepTrackingServiceProtocol,
        scheduler: any BackgroundTaskScheduling = BGTaskSchedulerAdapter()
    ) {
        self.stepTrackingService = stepTrackingService
        self.scheduler = scheduler
    }

    func registerTasks() {
        scheduler.register(forTaskWithIdentifier: AppConstants.BackgroundTaskIdentifiers.refresh) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                Loggers.background.error("background.refresh_task_cast_failed")
                task.setTaskCompleted(success: false)
                return
            }
            let boxedTask = BackgroundTaskBox(task: refreshTask)
            Task { @MainActor in
                self.handleAppRefresh(task: boxedTask.task)
            }
        }

        scheduler.register(forTaskWithIdentifier: AppConstants.BackgroundTaskIdentifiers.processing) { task in
            guard let processingTask = task as? BGProcessingTask else {
                Loggers.background.error("background.processing_task_cast_failed")
                task.setTaskCompleted(success: false)
                return
            }
            let boxedTask = BackgroundTaskBox(task: processingTask)
            Task { @MainActor in
                self.handleProcessing(task: boxedTask.task)
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
        let operation = Task { @MainActor in
            await performRefresh()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            operation.cancel()
        }
    }

    func handleProcessing(task: any ProcessingTaskProtocol) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        Task { @MainActor in
            task.setTaskCompleted(success: true)
        }
    }

    func performRefresh() async {
        await stepTrackingService.refreshTodayData()
    }
}
#endif
