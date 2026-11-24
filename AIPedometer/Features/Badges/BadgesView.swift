import SwiftUI

struct BadgesView: View {
    @Environment(BadgeService.self) private var badgeService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @State private var activeSheet: BadgeSheet?
    @State private var presentedCelebrationBadge: BadgeType?

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: DesignTokens.Spacing.smPlus)
    ]

    private var allBadges: [BadgeDisplayItem] {
        let earnedBadges = badgeService.earnedBadges()
        let earnedByType = Dictionary(uniqueKeysWithValues: earnedBadges.map { ($0.badgeType, $0) })
        return BadgeType.allCases
            .filter { $0.category != .challenge || earnedByType[$0] != nil }
            .map { type in
                BadgeDisplayItem(
                    type: type,
                    isEarned: earnedByType[type] != nil,
                    earnedBadge: earnedByType[type]
                )
            }
    }

    private var showsCustomBackButton: Bool {
        isPresented && LaunchConfiguration.isUITesting()
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
        .background {
            AmbientZenithBackground()
        }
        .navigationTitle(L10n.localized("Badges", comment: "Navigation title for badges"))
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(showsCustomBackButton)
        .toolbar {
            if showsCustomBackButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
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
        .sheet(item: $activeSheet, onDismiss: celebrationSheetDidDismiss) { sheet in
            switch sheet {
            case .celebration(let badgeType, let celebration):
                BadgeCelebrationSheet(
                    badgeType: badgeType,
                    celebration: celebration,
                    onDismiss: {
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
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                progressHeader(earnedCount: earnedBadges.count, totalCount: badgeItems.count)

                if earnedBadges.isEmpty {
                    emptyState
                }
                earnedSection(badges: earnedBadges)
                lockedSection(badges: lockedBadges)
            }
            .padding(.horizontal, DesignTokens.Spacing.mdPlus)
            .padding(.top, DesignTokens.Spacing.xs)
        }
        .tabBarAwareScrollContentBottomInset()
    }

    private func progressHeader(earnedCount: Int, totalCount: Int) -> some View {
        let ratio = totalCount > 0 ? Double(earnedCount) / Double(totalCount) : 0
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text(
                    Localization.format(
                        "%lld of %lld earned",
                        comment: "Badge progress summary",
                        Int64(earnedCount),
                        Int64(totalCount)
                    )
                )
                .font(DesignTokens.Typography.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

                Spacer()

                Text("\(ProgressClamp.percent(ratio))%")
                    .font(DesignTokens.Typography.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DesignTokens.Colors.accent)
            }

            ProgressView(value: ratio)
                .tint(DesignTokens.Colors.accent)
        }
        .padding(DesignTokens.Spacing.md)
        .calmCard()
    }

    @ViewBuilder
    private func earnedSection(badges: [BadgeDisplayItem]) -> some View {
        if !badges.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
                Text(L10n.localized("Earned", comment: "Section header for earned badges"))
                    .font(DesignTokens.Typography.headline)

                badgesGrid(badges: badges)
            }
        }
    }

    @ViewBuilder
    private func lockedSection(badges: [BadgeDisplayItem]) -> some View {
        if !badges.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
                Text(L10n.localized("Locked", comment: "Section header for locked badges"))
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                badgesGrid(badges: badges)
            }
        }
    }

    private func badgesGrid(badges: [BadgeDisplayItem]) -> some View {
        LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.smPlus) {
            ForEach(badges) { badge in
                BadgeCard(badge: badge) { selected in
                    if badgeService.celebratingBadge == nil {
                        activeSheet = .details(selected)
                    }
                }
            }
        }
        .glassContainer(spacing: DesignTokens.Spacing.smPlus)
    }

    private func updateCelebrationSheet() {
        guard activeSheet == nil, presentedCelebrationBadge == nil,
              let badgeType = badgeService.celebratingBadge,
              let celebration = badgeService.pendingCelebration else { return }
        presentedCelebrationBadge = badgeType
        activeSheet = .celebration(badgeType, celebration)
    }

    private func celebrationSheetDidDismiss() {
        if let presentedCelebrationBadge,
           badgeService.celebratingBadge == presentedCelebrationBadge {
            badgeService.dismissCelebration()
        }
        presentedCelebrationBadge = nil
        updateCelebrationSheet()
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
    @MainActor var description: String { type.localizedDescription }
    var icon: String { type.iconName }
}

private enum BadgeSheet: Identifiable {
    case celebration(BadgeType, AchievementCelebration)
    case details(BadgeDisplayItem)

    var id: String {
        switch self {
        case .celebration(let type, _):
            "celebration-\(type.rawValue)"
        case .details(let badge):
            "details-\(badge.id)"
        }
    }
}

// MARK: - Badge Card (Visual-First Trophy Tile)

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
            VStack(spacing: DesignTokens.Spacing.smPlus) {
                ZStack {
                    Circle()
                        .fill(
                            badge.isEarned
                                ? DesignTokens.Colors.yellow.opacity(0.16)
                                : DesignTokens.Colors.surfaceQuaternary
                        )
                        .frame(width: 60, height: 60)

                    Image(systemName: badge.icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(
                            badge.isEarned
                                ? AnyShapeStyle(DesignTokens.Colors.yellow.gradient)
                                : AnyShapeStyle(DesignTokens.Colors.textTertiary)
                        )
                        .saturation(badge.isEarned ? 1.0 : 0.0)
                }
                .accessibilityHidden(true)

                VStack(spacing: DesignTokens.Spacing.xxs) {
                    Text(badge.name)
                        .font(DesignTokens.Typography.subheadline.weight(.semibold))
                        .foregroundStyle(badge.isEarned ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if badge.isEarned, let earnedAt = badge.earnedAt {
                        Text(earnedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(DesignTokens.Typography.caption2)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DesignTokens.Sizing.badgeCardMinHeight)
            .calmCard()
            .overlay(alignment: .topTrailing) {
                if !badge.isEarned {
                    Image(systemName: "lock.fill")
                        .font(DesignTokens.Typography.caption2.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(DesignTokens.Spacing.smPlus)
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
}

// MARK: - Badge Detail Sheet

struct BadgeDetailSheet: View {
    let badge: BadgeDisplayItem
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(
                            badge.isEarned
                                ? DesignTokens.Colors.yellow.opacity(0.18)
                                : DesignTokens.Colors.surfaceQuaternary
                        )
                        .frame(width: 96, height: 96)

                    Image(systemName: badge.icon)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(
                            badge.isEarned
                                ? AnyShapeStyle(DesignTokens.Colors.yellow.gradient)
                                : AnyShapeStyle(DesignTokens.Colors.textSecondary)
                        )
                }
                .accessibilityHidden(true)

                VStack(spacing: DesignTokens.Spacing.sm) {
                    Text(L10n.localized("Badge Details", comment: "Badge detail sheet title"))
                        .font(DesignTokens.Typography.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)

                    Text(badge.name)
                        .font(DesignTokens.Typography.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(badge.description)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                if badge.isEarned, let earnedAt = badge.earnedAt {
                    Text(
                        Localization.format(
                            "Earned on %@",
                            comment: "Badge detail earned date",
                            earnedAt.formatted(date: .abbreviated, time: .omitted)
                        )
                    )
                    .font(DesignTokens.Typography.footnote.weight(.medium))
                    .foregroundStyle(DesignTokens.Colors.accent)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.xsPlus)
                    .background(DesignTokens.Colors.accentSoft, in: Capsule())
                } else {
                    Text(L10n.localized("Not earned yet", comment: "Badge detail locked message"))
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.top, DesignTokens.Spacing.xl)
            .padding(.bottom, DesignTokens.Spacing.lg)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                HapticService.shared.tap()
                onDismiss()
            } label: {
                Text(L10n.localized("Close", comment: "Badge detail close button"))
                    .font(DesignTokens.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.xs)
            }
            .glassButton()
            .controlSize(.large)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.top, DesignTokens.Spacing.sm)
            .padding(.bottom, DesignTokens.Spacing.md)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Badge Celebration Sheet

struct BadgeCelebrationSheet: View {
    let badgeType: BadgeType
    let celebration: AchievementCelebration
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xl) {
                Image(systemName: badgeType.iconName)
                    .font(.system(size: DesignTokens.FontSize.xxl))
                    .foregroundStyle(DesignTokens.Colors.yellow.gradient)
                    .breathingGlow(DesignTokens.Colors.yellow)
                    .accessibilityHidden(true)

                VStack(spacing: DesignTokens.Spacing.md) {
                    Text(badgeType.localizedTitle)
                        .font(DesignTokens.Typography.title.bold())
                        .multilineTextAlignment(.center)

                    Text(celebration.congratulation)
                        .font(DesignTokens.Typography.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)

                    Text(celebration.significance)
                        .font(DesignTokens.Typography.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                VStack(spacing: DesignTokens.Spacing.xs) {
                    Text(L10n.localized("Next Challenge", comment: "Badge celebration next challenge header"))
                        .font(DesignTokens.Typography.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)

                    Text(celebration.nextChallenge)
                        .font(DesignTokens.Typography.subheadline.weight(.medium))
                        .multilineTextAlignment(.center)
                }
                .padding(DesignTokens.Spacing.md)
                .frame(maxWidth: .infinity)
                .calmCard()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.top, DesignTokens.Spacing.xl)
            .padding(.bottom, DesignTokens.Spacing.lg)
        }
        .overlay {
            ConfettiView()
                .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                HapticService.shared.confirm()
                onDismiss()
            } label: {
                Text(L10n.localized("Continue", comment: "Badge celebration continue button"))
                    .font(DesignTokens.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.xs)
            }
            .glassButton()
            .controlSize(.large)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.top, DesignTokens.Spacing.sm)
            .padding(.bottom, DesignTokens.Spacing.md)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - BadgeType Extension

extension BadgeType {
    var iconName: String {
        switch self {
        case .steps5K, .steps10K, .steps15K, .steps20K, .steps25K:
            "figure.walk"
        case .streak3, .streak7, .streak14, .streak30, .streak100, .streak365:
            "flame.fill"
        case .distance5km, .distance10km, .distanceMarathon:
            "map.fill"
        case .monthlyChallenge:
            "star.fill"
        }
    }
}

#Preview {
    NavigationStack {
        BadgesView()
    }
    .environment(BadgeService(persistence: PersistenceController.shared))
}
