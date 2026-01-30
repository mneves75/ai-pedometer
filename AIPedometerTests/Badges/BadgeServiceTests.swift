import Foundation
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
}
