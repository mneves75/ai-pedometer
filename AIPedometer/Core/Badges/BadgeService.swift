import Foundation
import SwiftData
import FoundationModels

@MainActor
@Observable
final class BadgeService {
    private let persistence: PersistenceController
    private var foundationModelsService: FoundationModelsService?
    @ObservationIgnored private var didLoadEarnedBadges = false
    
    private(set) var earnedBadgesCache: [EarnedBadge] = []
    private(set) var pendingCelebration: AchievementCelebration?
    private(set) var celebratingBadge: BadgeType?

    init(persistence: PersistenceController) {
        self.persistence = persistence
        refreshEarnedBadges()
    }
    
    func configure(with aiService: FoundationModelsService) {
        self.foundationModelsService = aiService
    }

    @discardableResult
    func refreshEarnedBadges() -> [EarnedBadge] {
        let context = persistence.container.mainContext
        let descriptor = FetchDescriptor<EarnedBadge>(predicate: #Predicate { $0.deletedAt == nil })
        do {
            let badges = try context.fetch(descriptor)
            let dedupedBadges = deduplicateBadges(badges)
            if dedupedBadges.count != badges.count {
                Loggers.badges.warning("badges.duplicate_entries_detected", metadata: [
                    "total": "\(badges.count)",
                    "deduped": "\(dedupedBadges.count)"
                ])
            }
            earnedBadgesCache = dedupedBadges
            didLoadEarnedBadges = true
            return earnedBadgesCache
        } catch {
            Loggers.badges.error("badges.fetch_failed", metadata: ["error": error.localizedDescription])
            earnedBadgesCache = []
            didLoadEarnedBadges = true
            return earnedBadgesCache
        }
    }

    func earnedBadges() -> [EarnedBadge] {
        guard didLoadEarnedBadges else {
            return refreshEarnedBadges()
        }
        return earnedBadgesCache
    }

    func earnedBadgeTypes() -> Set<BadgeType> {
        Set(earnedBadges().map(\.badgeType))
    }

    @discardableResult
    func unlock(
        _ badgeType: BadgeType,
        metadata: [String: String] = [:],
        existingBadgeTypes: Set<BadgeType>? = nil
    ) -> Bool {
        let context = persistence.container.mainContext
        let earnedTypes = existingBadgeTypes ?? earnedBadgeTypes()
        guard !earnedTypes.contains(badgeType) else {
            return false
        }
        let badge = EarnedBadge(badgeType: badgeType, metadata: metadata)
        context.insert(badge)
        do {
            try context.save()
            Loggers.badges.info("badges.unlocked", metadata: [
                "badge": badgeType.rawValue
            ])
            refreshEarnedBadges()
            Task {
                await generateCelebration(for: badgeType)
            }
            return true
        } catch {
            Loggers.badges.error("badges.unlock_failed", metadata: [
                "badge": badgeType.rawValue,
                "error": error.localizedDescription
            ])
            return false
        }
    }
    
    func dismissCelebration() {
        pendingCelebration = nil
        celebratingBadge = nil
    }
    
    private func generateCelebration(for badgeType: BadgeType) async {
        guard let aiService = foundationModelsService,
              aiService.availability.isAvailable else { return }
        
        celebratingBadge = badgeType
        
        let prompt = """
        Generate a personalized achievement celebration for unlocking this badge:
        
        Badge: \(badgeType.displayName)
        Description: \(badgeType.badgeDescription)
        
        Create:
        1. A congratulatory message (1-2 sentences, enthusiastic)
        2. Why this achievement matters (1 sentence)
        3. A challenge or encouragement for what's next (1 sentence)
        """
        
        do {
            let celebration: AchievementCelebration = try await aiService.respond(
                to: prompt,
                as: AchievementCelebration.self
            )
            
            pendingCelebration = celebration
            
            Loggers.ai.info("ai.achievement_celebration_generated", metadata: [
                "badge": badgeType.rawValue
            ])
        } catch {
            Loggers.ai.error("ai.achievement_celebration_failed", metadata: [
                "badge": badgeType.rawValue,
                "error": error.localizedDescription
            ])
        }
    }

    private func deduplicateBadges(_ badges: [EarnedBadge]) -> [EarnedBadge] {
        let grouped = Dictionary(grouping: badges, by: \.badgeType)
        return grouped.values.compactMap { group in
            group.max(by: { $0.earnedAt < $1.earnedAt })
        }
    }
}

extension BadgeType {
    var displayName: String {
        localizedTitle
    }
    
    var badgeDescription: String {
        localizedDescription
    }
}
