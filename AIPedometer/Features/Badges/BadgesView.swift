import SwiftUI

struct BadgesView: View {
    @Environment(BadgeService.self) private var badgeService
    @Environment(\.presentationMode) private var presentationMode
    
    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: DesignTokens.Spacing.md)
    ]
    
    /// All available badge types for display
    private var allBadges: [BadgeDisplayItem] {
        let earnedBadges = badgeService.earnedBadges()
        let earnedByType = Dictionary(uniqueKeysWithValues: earnedBadges.map { ($0.badgeType, $0) })
        return BadgeType.allCases.map { type in
            BadgeDisplayItem(
                type: type,
                isEarned: earnedByType[type] != nil,
                earnedBadge: earnedByType[type]
            )
        }
    }

    private var showsCustomBackButton: Bool {
        presentationMode.wrappedValue.isPresented && LaunchConfiguration.isUITesting()
    }

    var body: some View {
        let badgeItems = allBadges
        let earnedBadges = badgeItems.filter(\.isEarned)
        let lockedBadges = badgeItems.filter { !$0.isEarned }

        scrollContent(
            badgeItems: badgeItems,
            earnedBadges: earnedBadges,
            lockedBadges: lockedBadges
        )
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "Badges", comment: "Navigation title for badges"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(showsCustomBackButton)
            .toolbar {
                if showsCustomBackButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            presentationMode.wrappedValue.dismiss()
                        } label: {
                            Label(String(localized: "Back", comment: "Back button label"), systemImage: "chevron.backward")
                        }
                        .accessibilityIdentifier("badges_back_button")
                    }
                }
            }
            .sheet(item: Binding(
                get: { badgeService.celebratingBadge.map { CelebratingBadgeWrapper(type: $0) } },
                set: { _ in badgeService.dismissCelebration() }
            )) { wrapper in
                if let celebration = badgeService.pendingCelebration {
                    BadgeCelebrationSheet(
                        badgeType: wrapper.type,
                        celebration: celebration,
                        onDismiss: { badgeService.dismissCelebration() }
                    )
                }
            }
    }
    
    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "No Badges Yet", comment: "Badges empty state title"), systemImage: "medal")
        } description: {
            Text(String(localized: "Keep walking to earn your first badge! Badges are awarded for reaching step milestones and maintaining streaks.", comment: "Badges empty state description"))
        }
    }
    
    private func scrollContent(
        badgeItems: [BadgeDisplayItem],
        earnedBadges: [BadgeDisplayItem],
        lockedBadges: [BadgeDisplayItem]
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                headerSection(earnedCount: earnedBadges.count, totalCount: badgeItems.count)
                if earnedBadges.isEmpty {
                    emptyState
                        .padding(.horizontal, DesignTokens.Spacing.md)
                }
                earnedSection(badges: earnedBadges)
                lockedSection(badges: lockedBadges)
            }
        }
    }

    private func headerSection(earnedCount: Int, totalCount: Int) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(String(localized: "Badges", comment: "Badges screen title"))
                .font(.largeTitle.bold())
            
            Text(
                Localization.format(
                    "%lld of %lld earned",
                    comment: "Badge progress summary",
                    Int64(earnedCount),
                    Int64(totalCount)
                )
            )
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.top, DesignTokens.Spacing.md)
    }
    
    @ViewBuilder
    private func earnedSection(badges: [BadgeDisplayItem]) -> some View {
        let earnedBadges = badges
        if !earnedBadges.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text(String(localized: "Earned", comment: "Section header for earned badges"))
                    .font(.headline)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                
                badgesGrid(badges: earnedBadges)
            }
        }
    }
    
    @ViewBuilder
    private func lockedSection(badges: [BadgeDisplayItem]) -> some View {
        let lockedBadges = badges
        if !lockedBadges.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text(String(localized: "Locked", comment: "Section header for locked badges"))
                    .font(.headline)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                
                badgesGrid(badges: lockedBadges)
            }
        }
    }
    
    @ViewBuilder
    private func badgesGrid(badges: [BadgeDisplayItem]) -> some View {
        if LaunchConfiguration.isUITesting() {
            badgesGridContent(badges: badges)
                .padding(.horizontal, DesignTokens.Spacing.md)
        } else if #available(iOS 26, *) {
            GlassEffectContainer(spacing: DesignTokens.Spacing.md) {
                badgesGridContent(badges: badges)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
        } else {
            badgesGridContent(badges: badges)
                .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    private func badgesGridContent(badges: [BadgeDisplayItem]) -> some View {
        LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.md) {
            ForEach(badges) { badge in
                BadgeCard(badge: badge)
            }
        }
    }
}

// MARK: - Supporting Types

struct BadgeDisplayItem: Identifiable {
    let id: String
    let type: BadgeType
    let isEarned: Bool
    let earnedAt: Date?
    
    init(type: BadgeType, isEarned: Bool, earnedBadge: EarnedBadge? = nil) {
        self.id = type.rawValue
        self.type = type
        self.isEarned = isEarned
        self.earnedAt = earnedBadge?.earnedAt
    }
    
    var name: String { type.localizedTitle }
    var description: String { type.localizedDescription }
    var icon: String { type.iconName }
}

private struct CelebratingBadgeWrapper: Identifiable {
    let type: BadgeType
    var id: String { type.rawValue }
}

// MARK: - Badge Card

struct BadgeCard: View {
    let badge: BadgeDisplayItem

    var body: some View {
        Button {
            if badge.isEarned {
                HapticService.shared.success()
            } else {
                HapticService.shared.tap()
            }
        } label: {
            VStack(spacing: DesignTokens.Spacing.sm) {
                badgeIcon
                badgeText
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .glassCard(interactive: badge.isEarned)
            .opacity(badge.isEarned ? 1.0 : 0.6)
            .saturation(badge.isEarned ? 1.0 : 0.0)
        }
        .buttonStyle(.plain)
        .accessibleCard(
            label: badge.name,
            hint: badge.isEarned 
                ? Localization.format(
                    "Badge earned: %@",
                    comment: "Accessibility hint for earned badge",
                    badge.description
                )
                : Localization.format(
                    "Not yet earned: %@",
                    comment: "Accessibility hint for unearned badge",
                    badge.description
                )
        )
    }

    private var badgeIcon: some View {
        Image(systemName: badge.icon)
            .font(.system(size: 40))
            .foregroundStyle(badge.isEarned ? AnyShapeStyle(.yellow.gradient) : AnyShapeStyle(.secondary))
            .applyIfNotUITesting { view in
                view.symbolEffect(.bounce, value: badge.isEarned)
            }
    }

    private var badgeText: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Text(badge.name)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(badge.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            if badge.isEarned, let earnedAt = badge.earnedAt {
                Text(earnedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Badge Celebration Sheet

struct BadgeCelebrationSheet: View {
    let badgeType: BadgeType
    let celebration: AchievementCelebration
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Spacer()
            
            Image(systemName: badgeType.iconName)
                .font(.system(size: 80))
                .foregroundStyle(.yellow.gradient)
                .applyIfNotUITesting { view in
                    view.symbolEffect(.bounce.up.byLayer, options: .repeating.speed(0.5))
                }
            
            VStack(spacing: DesignTokens.Spacing.md) {
                Text(badgeType.localizedTitle)
                    .font(.title.bold())
                
                Text(celebration.congratulation)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                
                Text(celebration.significance)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            
            Spacer()
            
            VStack(spacing: DesignTokens.Spacing.sm) {
                Text(String(localized: "Next Challenge", comment: "Badge celebration next challenge header"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                
                Text(celebration.nextChallenge)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            
            Button(String(localized: "Continue", comment: "Badge celebration continue button")) {
                HapticService.shared.confirm()
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, DesignTokens.Spacing.xl)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - BadgeType Extension

extension BadgeType {
    var iconName: String {
        switch self {
        case .steps5K, .steps10K, .steps15K, .steps20K, .steps25K:
            return "figure.walk"
        case .streak3, .streak7, .streak14, .streak30, .streak100, .streak365:
            return "flame.fill"
        case .distance5km, .distance10km, .distanceMarathon:
            return "map.fill"
        case .monthlyChallenge:
            return "star.fill"
        }
    }
}

#Preview {
    BadgesView()
        .environment(BadgeService(persistence: PersistenceController.shared))
}
