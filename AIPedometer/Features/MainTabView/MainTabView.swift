import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Tab = .dashboard
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
            case .dashboard: String(localized: "Dashboard", comment: "Tab title for main dashboard")
            case .history: String(localized: "History", comment: "Tab title for step history")
            case .workouts: String(localized: "Workouts", comment: "Tab title for workouts list")
            case .badges: String(localized: "Badges", comment: "Tab title for achievements/badges")
            case .aiCoach: String(localized: "AI Coach", comment: "Tab title for AI coach chat")
            case .settings: String(localized: "Settings", comment: "Tab title for app settings")
            case .more: String(localized: "More", comment: "Tab title for more options")
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
                true
            case .badges, .settings:
                false
            }
        }

        var isTabletTab: Bool {
            self != .more
        }
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            ForEach(Tab.allCases.filter(\.isPhoneTab), id: \.self) { tab in
                tabRoot(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
        .tint(.blue)
        #if os(iOS)
        .toolbarBackground(.ultraThickMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        #endif
        .accessibilityIdentifier("main_tab_bar")
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            List {
                ForEach(Tab.allCases.filter(\.isTabletTab), id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        selectedTab == tab
                            ? Color.accentColor.opacity(0.2)
                            : Color.clear
                    )
                }
            }
            .navigationTitle("AI Pedometer")
            .listStyle(.sidebar)
        } detail: {
            NavigationStack {
                tabContent(for: selectedTab)
            }
        }
        .accessibilityIdentifier("main_split_view")
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

#Preview("iPhone") {
    MainTabView()
        .environment(\.horizontalSizeClass, .compact)
}

#Preview("iPad") {
    MainTabView()
        .environment(\.horizontalSizeClass, .regular)
}
