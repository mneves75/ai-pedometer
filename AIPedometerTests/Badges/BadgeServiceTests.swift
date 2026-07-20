import Foundation
import SwiftData
import Testing

@testable import AIPedometer

@Suite("BadgeService")
@MainActor
struct BadgeServiceTests {
    @Test("Unlock persists new badge")
    func unlockPersistsBadge() {
        let persistence = PersistenceController(inMemory: true)
        let service = BadgeService(persistence: persistence)

        let unlocked = service.unlock(.steps5K, metadata: ["steps": "5000"])

        #expect(unlocked == true)
        let earned = service.earnedBadges()
        #expect(earned.count == 1)
        #expect(earned.first?.badgeType == .steps5K)
        #expect(earned.first?.metadata["steps"] == "5000")
    }

    @Test("Unlock is idempotent")
    func unlockIsIdempotent() {
        let persistence = PersistenceController(inMemory: true)
        let service = BadgeService(persistence: persistence)

        let firstUnlock = service.unlock(.steps10K)
        let secondUnlock = service.unlock(.steps10K)

        #expect(firstUnlock == true)
        #expect(secondUnlock == false)
        let earned = service.earnedBadges().filter { $0.badgeType == .steps10K }
        #expect(earned.count == 1)
    }

    @Test("Failed unlock does not persist a badge on a later save")
    func failedUnlockDoesNotPersistBadgeOnLaterSave() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let service = BadgeService(
            persistence: persistence,
            saveModelContext: { _ in throw CocoaError(.fileWriteUnknown) }
        )

        #expect(service.unlock(.steps10K) == false)
        try context.save()

        let badges = try context.fetch(FetchDescriptor<EarnedBadge>())
        #expect(badges.isEmpty)
    }

    @Test("earnedBadges excludes deleted badges")
    func earnedBadgesExcludesDeleted() throws {
        let persistence = PersistenceController(inMemory: true)
        let service = BadgeService(persistence: persistence)
        let context = persistence.container.mainContext

        context.insert(EarnedBadge(badgeType: .steps5K))
        context.insert(EarnedBadge(badgeType: .steps10K, deletedAt: .now))
        try context.save()

        let earned = service.refreshEarnedBadges()
        #expect(earned.count == 1)
        #expect(earned.first?.badgeType == .steps5K)
    }

    @Test("earnedBadgesCache updates after unlock")
    func earnedBadgesCacheUpdatesAfterUnlock() {
        let persistence = PersistenceController(inMemory: true)
        let service = BadgeService(persistence: persistence)

        #expect(service.earnedBadgesCache.isEmpty)

        let unlocked = service.unlock(.steps5K)

        #expect(unlocked == true)
        #expect(service.earnedBadgesCache.contains { $0.badgeType == .steps5K })
    }

    @Test("Badge celebration is gated by AI coaching permission")
    func celebrationGatedByAICoachingPermission() async {
        let persistence = PersistenceController(inMemory: true)
        let service = BadgeService(persistence: persistence)
        let mockAI = MockFoundationModelsService()
        mockAI.availability = .available
        service.configure(with: mockAI, canGenerateAICoaching: { false })

        let unlocked = service.unlock(.steps5K)
        #expect(unlocked == true)
        await service.pendingCelebrationTask?.value

        #expect(service.celebratingBadge == nil)
        #expect(service.pendingCelebration == nil)
        #expect(mockAI.respondCallCount == 0)
    }

    @Test("Badge celebration is skipped when AI is unavailable even if coaching is allowed")
    func celebrationSkippedWhenAIUnavailable() async {
        let persistence = PersistenceController(inMemory: true)
        let service = BadgeService(persistence: persistence)
        let mockAI = MockFoundationModelsService()
        mockAI.availability = .unavailable(reason: .modelNotReady)
        service.configure(with: mockAI, canGenerateAICoaching: { true })

        let unlocked = service.unlock(.streak3)
        #expect(unlocked == true)
        await service.pendingCelebrationTask?.value

        #expect(service.celebratingBadge == nil)
        #expect(service.pendingCelebration == nil)
        #expect(mockAI.respondCallCount == 0)
    }

    @Test("A failed AI celebration releases the badge detail gate")
    func failedCelebrationReleasesBadgeDetailGate() async {
        let persistence = PersistenceController(inMemory: true)
        let service = BadgeService(persistence: persistence)
        let mockAI = MockFoundationModelsService()
        mockAI.availability = .available
        mockAI.respondResult = .failure(.generationFailed(underlying: "celebration unavailable"))
        service.configure(with: mockAI, canGenerateAICoaching: { true })

        let unlocked = service.unlock(.streak7)
        #expect(unlocked == true)
        await service.pendingCelebrationTask?.value

        #expect(mockAI.respondCallCount == 1)
        #expect(service.pendingCelebration == nil)
        #expect(service.celebratingBadge == nil)
    }

    @Test("Dismissing an in-flight celebration prevents a late response from republishing it")
    func dismissingInFlightCelebrationPreventsLatePublication() async throws {
        let persistence = PersistenceController(inMemory: true)
        let service = BadgeService(persistence: persistence)
        let modelStarted = BadgeTestLatch()
        let releaseModel = BadgeTestLatch()
        let mockAI = MockFoundationModelsService()
        mockAI.availability = .available
        mockAI.beforeRespond = {
            modelStarted.signal()
            await releaseModel.wait()
        }
        mockAI.respondResult = .success(Self.celebration(message: "Late response"))
        service.configure(with: mockAI, canGenerateAICoaching: { true })

        #expect(service.unlock(.streak7))
        let generationTask = try #require(service.pendingCelebrationTask)
        await modelStarted.wait()

        service.dismissCelebration()
        releaseModel.signal()
        await generationTask.value

        #expect(mockAI.respondCallCount == 1)
        #expect(service.pendingCelebration == nil)
        #expect(service.celebratingBadge == nil)
        #expect(service.pendingCelebrationTask == nil)
    }

    @Test("A replaced celebration generation cannot clear or publish over the current result")
    func replacedCelebrationCannotMutateCurrentResult() async throws {
        let persistence = PersistenceController(inMemory: true)
        let service = BadgeService(persistence: persistence)
        let firstModelStarted = BadgeTestLatch()
        let releaseFirstModel = BadgeTestLatch()
        let secondModelStarted = BadgeTestLatch()
        let mockAI = MockFoundationModelsService()
        mockAI.availability = .available
        mockAI.beforeRespond = {
            if mockAI.respondCallCount == 1 {
                firstModelStarted.signal()
                await releaseFirstModel.wait()
            } else {
                secondModelStarted.signal()
            }
        }
        mockAI.respondResult = .success(Self.celebration(message: "Current response"))
        service.configure(with: mockAI, canGenerateAICoaching: { true })

        #expect(service.unlock(.streak7))
        let replacedTask = try #require(service.pendingCelebrationTask)
        await firstModelStarted.wait()

        #expect(service.unlock(.steps10K))
        let currentTask = try #require(service.pendingCelebrationTask)
        await secondModelStarted.wait()
        await currentTask.value

        #expect(service.celebratingBadge == .steps10K)
        #expect(service.pendingCelebration?.congratulation == "Current response")

        releaseFirstModel.signal()
        await replacedTask.value

        #expect(mockAI.respondCallCount == 2)
        #expect(service.celebratingBadge == .steps10K)
        #expect(service.pendingCelebration?.congratulation == "Current response")
        #expect(service.pendingCelebrationTask == nil)
    }

    @Test("refreshEarnedBadges deduplicates duplicate badge types")
    func refreshEarnedBadgesDeduplicatesDuplicateBadgeTypes() throws {
        let persistence = PersistenceController(inMemory: true)
        let service = BadgeService(persistence: persistence)
        let context = persistence.container.mainContext
        let older = EarnedBadge(
            badgeType: .steps5K,
            earnedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = EarnedBadge(
            badgeType: .steps5K,
            earnedAt: Date(timeIntervalSince1970: 2_000)
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        let earned = service.refreshEarnedBadges().filter { $0.badgeType == .steps5K }
        #expect(earned.count == 1)
        #expect(earned.first?.earnedAt == newer.earnedAt)
    }

    private static func celebration(message: String) -> AchievementCelebration {
        AchievementCelebration(
            congratulation: message,
            significance: "Meaningful progress",
            nextChallenge: "Keep going"
        )
    }
}

@MainActor
private final class BadgeTestLatch {
    private var isSignaled = false

    func wait(timeout: Duration = .seconds(5)) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while !isSignaled {
            if Task.isCancelled { return }
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for a badge test rendezvous")
                signal()
                return
            }
            await Task.yield()
        }
    }

    func signal() {
        guard !isSignaled else { return }
        isSignaled = true
    }
}
