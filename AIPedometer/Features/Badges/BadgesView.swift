import SwiftUI

struct BadgesView: View {
    @Environment(BadgeService.self) private var badgeService
    @Environment(\.presentationMode) private var presentationMode
    @State private var activeSheet: BadgeSheet?
    
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
        .uiTestMarker(A11yID.Badges.marker)
        .background(DesignTokens.Colors.surfaceGrouped)
            .navigationTitle(L10n.localized("Badges", comment: "Navigation title for badges"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(showsCustomBackButton)
            .toolbar {
                if showsCustomBackButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            presentationMode.wrappedValue.dismiss()
                        } label: {
                            Label(L10n.localized("Back", comment: "Back button label"), systemImage: "chevron.backward")
                        }
                        .accessibilityIdentifier("badges_back_button")
                    }
                }
            }
            .task {
                updateCelebrationSheet()
            }
            .onChange(of: badgeService.pendingCelebration != nil) { _, _ in
                updateCelebrationSheet()
            }
            .onChange(of: badgeService.celebratingBadge) { _, newValue in
                if newValue == nil, case .celebration = activeSheet {
                    activeSheet = nil
                }
                updateCelebrationSheet()
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .celebration(let badgeType, let celebration):
                    BadgeCelebrationSheet(
                        badgeType: badgeType,
                        celebration: celebration,
                        onDismiss: {
                            badgeService.dismissCelebration()
                            activeSheet = nil
                        }
                    )
                case .details(let badge):
                    BadgeDetailSheet(badge: badge) {
                        activeSheet = nil
                    }
                }
            }
    }
    
    private var emptyState: some View {
        ContentUnavailableView {
            Label(L10n.localized("No Badges Yet", comment: "Badges empty state title"), systemImage: "medal")
        } description: {
            Text(L10n.localized("Keep walking to earn your first badge! Badges are awarded for reaching step milestones and maintaining streaks.", comment: "Badges empty state description"))
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
            Text(L10n.localized("Badges", comment: "Badges screen title"))
                .font(DesignTokens.Typography.largeTitle.bold())
            
            Text(
                Localization.format(
                    "%lld of %lld earned",
                    comment: "Badge progress summary",
                    Int64(earnedCount),
                    Int64(totalCount)
                )
            )
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.top, DesignTokens.Spacing.md)
    }
    
    @ViewBuilder
    private func earnedSection(badges: [BadgeDisplayItem]) -> some View {
        let earnedBadges = badges
        if !earnedBadges.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text(L10n.localized("Earned", comment: "Section header for earned badges"))
                    .font(DesignTokens.Typography.headline)
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
                Text(L10n.localized("Locked", comment: "Section header for locked badges"))
                    .font(DesignTokens.Typography.headline)
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
                BadgeCard(badge: badge) { selected in
                    if badgeService.celebratingBadge == nil {
                        activeSheet = .details(selected)
                    }
                }
            }
        }
    }

    private func updateCelebrationSheet() {
        guard let badgeType = badgeService.celebratingBadge,
              let celebration = badgeService.pendingCelebration else { return }
        activeSheet = .celebration(badgeType, celebration)
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

private enum BadgeSheet: Identifiable {
    case celebration(BadgeType, AchievementCelebration)
    case details(BadgeDisplayItem)

    var id: String {
        switch self {
        case .celebration(let type, _):
            return "celebration-\(type.rawValue)"
        case .details(let badge):
            return "details-\(badge.id)"
        }
    }
}

// MARK: - Badge Card

struct BadgeCard: View {
    let badge: BadgeDisplayItem
    let onSelect: (BadgeDisplayItem) -> Void

    var body: some View {
        Button {
            if badge.isEarned {
                HapticService.shared.success()
            } else {
                HapticService.shared.tap()
            }
            onSelect(badge)
        } label: {
            VStack(spacing: DesignTokens.Spacing.sm) {
                badgeIcon
                badgeText
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .glassCard(interactive: badge.isEarned)
            .opacity(badge.isEarned ? 1.0 : 0.45)
            .saturation(badge.isEarned ? 1.0 : 0.1)
            .overlay(alignment: .topTrailing) {
                if !badge.isEarned {
                    Image(systemName: "lock.fill")
                        .font(DesignTokens.Typography.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(DesignTokens.Spacing.sm)
                        .accessibilityHidden(true)
                }
            }
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
            .font(.system(size: DesignTokens.FontSize.xs))
            .foregroundStyle(badge.isEarned ? AnyShapeStyle(DesignTokens.Colors.yellow.gradient) : AnyShapeStyle(DesignTokens.Colors.textSecondary))
            .applyIfNotUITesting { view in
                view.symbolEffect(.bounce, value: badge.isEarned)
            }
    }

    private var badgeText: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Text(badge.name)
                .font(DesignTokens.Typography.headline)
                .multilineTextAlignment(.center)

            Text(badge.description)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            if badge.isEarned, let earnedAt = badge.earnedAt {
                Text(earnedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
    }
}

// MARK: - Badge Detail Sheet

struct BadgeDetailSheet: View {
    let badge: BadgeDisplayItem
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: badge.icon)
                .font(.system(size: DesignTokens.FontSize.xl))
                .foregroundStyle(badge.isEarned ? AnyShapeStyle(DesignTokens.Colors.yellow.gradient) : AnyShapeStyle(DesignTokens.Colors.textSecondary))

            VStack(spacing: DesignTokens.Spacing.sm) {
                Text(L10n.localized("Badge Details", comment: "Badge detail sheet title"))
                    .font(DesignTokens.Typography.title3.bold())

                Text(badge.name)
                    .font(DesignTokens.Typography.headline)

                Text(badge.description)
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)

            if badge.isEarned, let earnedAt = badge.earnedAt {
                Text(
                    Localization.format(
                        "Earned on %@",
                        comment: "Badge detail earned date",
                        earnedAt.formatted(date: .abbreviated, time: .omitted)
                    )
                )
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            } else {
                Text(L10n.localized("Not earned yet", comment: "Badge detail locked message"))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Button(L10n.localized("Close", comment: "Badge detail close button")) {
                HapticService.shared.tap()
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

// MARK: - Badge Celebration Sheet

struct BadgeCelebrationSheet: View {
    let badgeType: BadgeType
    let celebration: AchievementCelebration
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Spacer()
            
            Image(systemName: badgeType.iconName)
                .font(.system(size: DesignTokens.FontSize.xxl))
                .foregroundStyle(DesignTokens.Colors.yellow.gradient)
                .applyIfNotUITesting { view in
                    view.symbolEffect(.bounce.up.byLayer, options: .repeating.speed(0.5))
                }
            
            VStack(spacing: DesignTokens.Spacing.md) {
                Text(badgeType.localizedTitle)
                    .font(DesignTokens.Typography.title.bold())
                
                Text(celebration.congratulation)
                    .font(DesignTokens.Typography.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                
                Text(celebration.significance)
                    .font(DesignTokens.Typography.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            
            Spacer()
            
            VStack(spacing: DesignTokens.Spacing.sm) {
                Text(L10n.localized("Next Challenge", comment: "Badge celebration next challenge header"))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                
                Text(celebration.nextChallenge)
                    .font(DesignTokens.Typography.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            
            Button(L10n.localized("Continue", comment: "Badge celebration continue button")) {
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
