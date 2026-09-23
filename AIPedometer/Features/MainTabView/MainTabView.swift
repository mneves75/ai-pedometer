import SwiftUI

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: Tab = .dashboard
    @State private var preferredRegularTab: Tab = .dashboard

    enum Layout: Equatable {
        case compact
        case regular
    }

    enum Tab: String, CaseIterable {
        case dashboard
        case history
        case workouts
        case badges
        case aiCoach
        case settings
        case more

        var title: String {
            switch self {
            case .dashboard: L10n.localized("Dashboard", comment: "Tab title for main dashboard")
            case .history: L10n.localized("History", comment: "Tab title for step history")
            case .workouts: L10n.localized("Workouts", comment: "Tab title for workouts list")
            case .badges: L10n.localized("Badges", comment: "Tab title for achievements/badges")
            case .aiCoach: L10n.localized("AI Coach", comment: "Tab title for AI coach chat")
            case .settings: L10n.localized("Settings", comment: "Tab title for app settings")
            case .more: L10n.localized("More", comment: "Tab title for more options")
            }
        }

        var icon: String {
            switch self {
            case .dashboard: "figure.walk"
            case .history: "calendar"
            case .workouts: "figure.run"
            case .badges: "medal.fill"
            case .aiCoach: "sparkles"
            case .settings: "gearshape.fill"
            case .more: "ellipsis.circle"
            }
        }

        var isPhoneTab: Bool {
            switch self {
            case .dashboard, .history, .workouts, .aiCoach, .more:
                return true
            case .badges, .settings:
                return false
            }
        }

        var isTabletTab: Bool {
            self != .more
        }
    }

    private var layout: Layout {
        horizontalSizeClass == .regular ? .regular : .compact
    }

    static func normalizedSelection(_ selection: Tab, for layout: Layout) -> Tab {
        switch layout {
        case .compact:
            selection.isPhoneTab ? selection : .more
        case .regular:
            selection.isTabletTab ? selection : .dashboard
        }
    }

    static func transitionedSelection(
        _ selection: Tab,
        preferredRegularSelection: Tab,
        to layout: Layout
    ) -> (selection: Tab, preferredRegularSelection: Tab) {
        let preferredSelection = selection.isTabletTab ? selection : preferredRegularSelection

        switch layout {
        case .compact:
            return (normalizedSelection(selection, for: layout), preferredSelection)
        case .regular:
            let selectionToRestore = selection == .more ? preferredSelection : selection
            let restoredSelection = normalizedSelection(selectionToRestore, for: layout)
            return (restoredSelection, restoredSelection)
        }
    }

    var body: some View {
        Group {
            if layout == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .onChange(of: layout, initial: true) { _, newLayout in
            let transition = Self.transitionedSelection(
                selectedTab,
                preferredRegularSelection: preferredRegularTab,
                to: newLayout
            )
            preferredRegularTab = transition.preferredRegularSelection
            selectedTab = transition.selection
        }
        .onChange(of: selectedTab) { _, newSelection in
            guard newSelection != .more else { return }
            preferredRegularTab = newSelection
        }
    }

    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            ForEach(Tab.allCases.filter(\.isPhoneTab), id: \.self) { tab in
                SwiftUI.Tab(value: tab) {
                    tabRoot(for: tab)
                } label: {
                    Label(tab.title, systemImage: tab.icon)
                        .accessibilityIdentifier(A11yID.tab(tab.rawValue))
                }
            }
        }
        .tint(DesignTokens.Colors.accent)
        #if os(iOS)
        .toolbarBackground(.ultraThickMaterial, for: .tabBar)
        .toolbarBackgroundVisibility(.visible, for: .tabBar)
        #endif
        .accessibilityIdentifier(A11yID.mainTabBar)
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            List {
                ForEach(Tab.allCases.filter(\.isTabletTab), id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11yID.tab(tab.rawValue))
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    .listRowBackground(
                        selectedTab == tab
                            ? DesignTokens.Colors.accentMuted
                            : Color.clear
                    )
                }
            }
            .navigationTitle(L10n.localized("AI Pedometer", comment: "Sidebar title for main navigation"))
            .listStyle(.sidebar)
        } detail: {
            NavigationStack {
                tabContent(for: selectedTab)
            }
            // One stack serves every sidebar item, and pushes use destination links that no path binding
            // records. A new identity per selection resets the stack, so a detail pushed under one item
            // (Workouts → Training Plan) cannot stay above the next item's root.
            .id(selectedTab)
        }
        .accessibilityIdentifier(A11yID.mainSplitView)
    }

    private func tabRoot(for tab: Tab) -> some View {
        NavigationStack {
            tabContent(for: tab)
        }
    }

    @ViewBuilder
    private func tabContent(for tab: Tab) -> some View {
        switch tab {
        case .dashboard:
            DashboardView()
        case .history:
            HistoryView()
        case .workouts:
            WorkoutsView()
        case .badges:
            BadgesView()
        case .aiCoach:
            AICoachView()
        case .settings:
            SettingsView()
        case .more:
            MoreView()
        }
    }
}

#if DEBUG
// Both the previews and their helper are Debug-only: a `#Preview` body is still type-checked in Release,
// so a preview calling a `#if DEBUG` member breaks the Release (archive) build.
#Preview("iPhone") {
    MainTabView.previewWithServices(.compact)
}

#Preview("iPad") {
    MainTabView.previewWithServices(.regular)
}

extension MainTabView {
    /// Every tab root reads services from the environment; without them the preview crashes at runtime
    /// even though it builds. Mirrors the injection in `AIPedometerApp` with demo and in-memory backends.
    @MainActor
    static func previewWithServices(_ sizeClass: UserInterfaceSizeClass) -> some View {
        let persistence = PersistenceController(inMemory: true)
        let modelContext = persistence.container.mainContext
        let demoModeStore = DemoModeStore()
        let healthKitService = HealthKitServiceFallback(demoModeStore: demoModeStore)
        let healthAuthorization = HealthKitAuthorization()
        let fmService = FoundationModelsService()
        let goalService = GoalService(persistence: persistence)
        let badgeService = BadgeService(persistence: persistence)
        let dataStore = SharedDataStore()
        let trackingService = StepTrackingService(
            healthKitService: healthKitService,
            motionService: MotionService(),
            healthAuthorization: healthAuthorization,
            goalService: goalService,
            badgeService: badgeService,
            dataStore: dataStore,
            streakCalculator: StreakCalculator(stepAggregator: StepDataAggregator(), goalService: goalService)
        )

        return MainTabView()
            .environment(\.horizontalSizeClass, sizeClass)
            .environment(healthAuthorization)
            .environment(trackingService)
            .environment(fmService)
            .environment(InsightService(
                foundationModelsService: fmService,
                healthKitService: healthKitService,
                goalService: goalService,
                dataStore: dataStore
            ))
            .environment(CoachService(
                foundationModelsService: fmService,
                healthKitService: healthKitService,
                goalService: goalService
            ))
            .environment(TrainingPlanService(
                foundationModelsService: fmService,
                healthKitService: healthKitService,
                goalService: goalService,
                modelContext: modelContext
            ))
            .environment(WorkoutSessionController(
                modelContext: modelContext,
                healthKitService: healthKitService,
                metricsSource: MotionLiveMetricsSource(motionService: MotionService()),
                liveActivityManager: NoopLiveActivityManager()
            ))
            .environment(badgeService)
            .environment(HealthKitSyncService(
                healthKitService: healthKitService,
                modelContext: modelContext,
                goalService: goalService
            ))
            .environment(demoModeStore)
            .environment(NotificationService())
            .environment(SmartNotificationService(
                foundationModelsService: fmService,
                healthKitService: healthKitService,
                goalService: goalService
            ))
            .environment(TipJarStore())
            .modelContainer(persistence.container)
    }
}
#endif
