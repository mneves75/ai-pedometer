import Foundation
import SwiftData
import FoundationModels

@MainActor
@Observable
final class BadgeService {
    private let persistence: PersistenceController
    private let saveModelContext: @MainActor (ModelContext) throws -> Void
    private var foundationModelsService: (any FoundationModelsServiceProtocol)?
    @ObservationIgnored private var didLoadEarnedBadges = false
    @ObservationIgnored private var canGenerateAICoaching: @MainActor @Sendable () -> Bool = { false }

    private(set) var earnedBadgesCache: [EarnedBadge] = []
    private(set) var pendingCelebration: AchievementCelebration?
    private(set) var celebratingBadge: BadgeType?
    @ObservationIgnored private(set) var pendingCelebrationTask: Task<Void, Never>?
    @ObservationIgnored private var celebrationGeneration: UUID?

    init(
        persistence: PersistenceController,
        saveModelContext: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.persistence = persistence
        self.saveModelContext = saveModelContext
        refreshEarnedBadges()
    }

    /// Wire up the AI service and the premium gate. The badge celebration generator only runs
    /// when both AI availability and `canGenerateAICoaching()` are true, keeping AI coaching
    /// behind the same fail-closed premium boundary as the rest of the AI surfaces.
    func configure(
        with aiService: any FoundationModelsServiceProtocol,
        canGenerateAICoaching: @escaping @MainActor @Sendable () -> Bool = { false }
    ) {
        self.foundationModelsService = aiService
        self.canGenerateAICoaching = canGenerateAICoaching
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
            try saveModelContext(context)
            Loggers.badges.info("badges.unlocked", metadata: [
                "badge": badgeType.rawValue
            ])
            refreshEarnedBadges()
            startCelebration(for: badgeType)
            return true
        } catch {
            context.delete(badge)
            Loggers.badges.error("badges.unlock_failed", metadata: [
                "badge": badgeType.rawValue,
                "error": error.localizedDescription
            ])
            return false
        }
    }
    
    func dismissCelebration() {
        celebrationGeneration = nil
        pendingCelebrationTask?.cancel()
        pendingCelebrationTask = nil
        pendingCelebration = nil
        celebratingBadge = nil
    }

    private func startCelebration(for badgeType: BadgeType) {
        celebrationGeneration = nil
        pendingCelebrationTask?.cancel()
        pendingCelebration = nil
        celebratingBadge = nil

        let generation = UUID()
        celebrationGeneration = generation
        pendingCelebrationTask = Task { [weak self] in
            await self?.generateCelebration(for: badgeType, generation: generation)
        }
    }

    private func generateCelebration(for badgeType: BadgeType, generation: UUID) async {
        var didPublishCelebration = false
        defer {
            finishCelebrationGeneration(generation, preservingCelebration: didPublishCelebration)
        }

        guard celebrationGeneration == generation, !Task.isCancelled else { return }
        guard canGenerateAICoaching() else { return }
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

            guard celebrationGeneration == generation, !Task.isCancelled else { return }
            pendingCelebration = celebration
            didPublishCelebration = true
            
            Loggers.ai.info("ai.achievement_celebration_generated", metadata: [
                "badge": badgeType.rawValue
            ])
        } catch {
            guard celebrationGeneration == generation, !Task.isCancelled else { return }
            Loggers.ai.error("ai.achievement_celebration_failed", metadata: [
                "badge": badgeType.rawValue,
                "error": error.localizedDescription
            ])
        }
    }

    private func finishCelebrationGeneration(
        _ generation: UUID,
        preservingCelebration: Bool
    ) {
        guard celebrationGeneration == generation else { return }
        celebrationGeneration = nil
        pendingCelebrationTask = nil
        if !preservingCelebration {
            pendingCelebration = nil
            celebratingBadge = nil
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
