import Foundation
import Observation

@Observable
@MainActor
final class SharedDataStore {
    typealias FlushScheduler = @MainActor (
        _ delay: TimeInterval,
        _ operation: @escaping @MainActor @Sendable () -> Void
    ) -> Void

    private(set) var sharedData: SharedStepData?
    private let userDefaults: UserDefaults?
    private let coalescingInterval: TimeInterval
    private let now: () -> Date
    private let scheduleFlush: FlushScheduler
    private var lastPersistedData: SharedStepData?
    private var lastPersistedAt: Date?
    private var pendingData: SharedStepData?
    private var hasScheduledFlush = false
    private var flushGeneration = 0
    private(set) var persistedWriteCount = 0
    private(set) var coalescedUpdateCount = 0

    init(
        userDefaults: UserDefaults? = .sharedAppGroup,
        coalescingInterval: TimeInterval = 0,
        now: @escaping () -> Date = { .now },
        scheduleFlush: @escaping FlushScheduler = { delay, operation in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                operation()
            }
        }
    ) {
        self.userDefaults = userDefaults
        self.coalescingInterval = max(coalescingInterval, 0)
        self.now = now
        self.scheduleFlush = scheduleFlush
    }

    func refresh() {
        sharedData = userDefaults?.sharedStepData
    }

    func update(_ data: SharedStepData) {
        sharedData = data
        let timestamp = now()
        if SharedStepDataWritePolicy.shouldPersistImmediately(
            previous: lastPersistedData,
            next: data,
            lastPersistedAt: lastPersistedAt,
            now: timestamp,
            maximumStaleness: coalescingInterval
        ) {
            persist(data, at: timestamp)
            return
        }

        pendingData = data
        coalescedUpdateCount += 1
        Signposts.sync.event("SharedStepDataCoalesced")
        guard !hasScheduledFlush else { return }
        hasScheduledFlush = true
        flushGeneration &+= 1
        let scheduledGeneration = flushGeneration
        let elapsed = max(timestamp.timeIntervalSince(lastPersistedAt ?? timestamp), 0)
        let remaining = max(coalescingInterval - elapsed, 0)
        scheduleFlush(remaining) { [weak self] in
            self?.flush(ifGenerationMatches: scheduledGeneration)
        }
    }

    func flush() {
        guard let pendingData else {
            invalidateScheduledFlush()
            return
        }
        persist(pendingData, at: now())
    }

    private func flush(ifGenerationMatches scheduledGeneration: Int) {
        guard hasScheduledFlush, flushGeneration == scheduledGeneration else { return }
        flush()
    }

    private func invalidateScheduledFlush() {
        flushGeneration &+= 1
        hasScheduledFlush = false
    }

    private func persist(_ data: SharedStepData, at timestamp: Date) {
        pendingData = nil
        invalidateScheduledFlush()
        lastPersistedData = data
        lastPersistedAt = timestamp
        guard let userDefaults else {
            Loggers.sync.error("shared_step_data_write_skipped", metadata: [
                "reason": "app_group_unavailable"
            ])
            return
        }
        let state = Signposts.sync.begin("SharedStepDataWrite")
        defer { Signposts.sync.end("SharedStepDataWrite", state) }
        userDefaults.sharedStepData = data
        persistedWriteCount += 1
        Signposts.sync.event("SharedStepDataPersisted")
    }
}

enum SharedStepDataWritePolicy {
    static func shouldPersistImmediately(
        previous: SharedStepData?,
        next: SharedStepData,
        lastPersistedAt: Date?,
        now: Date,
        maximumStaleness: TimeInterval,
        milestoneDelta: Int = 100,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard maximumStaleness > 0, let previous, let lastPersistedAt else { return true }
        if now.timeIntervalSince(lastPersistedAt) >= maximumStaleness { return true }
        if !calendar.isDate(previous.lastUpdated, inSameDayAs: next.lastUpdated) { return true }
        if previous.goalSteps != next.goalSteps ||
            previous.currentStreak != next.currentStreak ||
            previous.weeklySteps != next.weeklySteps {
            return true
        }
        return abs(next.todaySteps - previous.todaySteps) >= milestoneDelta
    }
}
