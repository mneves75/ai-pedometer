import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.onboardingCompleted) private var onboardingCompleted = true
    @AppStorage(AppConstants.UserDefaultsKeys.activityTrackingMode) private var activityModeRaw = ActivityTrackingMode.steps.rawValue
    @AppStorage(AppConstants.UserDefaultsKeys.distanceEstimationMode) private var distanceModeRaw = DistanceEstimationMode.automatic.rawValue
    @AppStorage(AppConstants.UserDefaultsKeys.manualStepLengthMeters) private var manualStepLength = AppConstants.Defaults.manualStepLengthMeters
    @AppStorage(AppConstants.UserDefaultsKeys.healthKitSyncEnabled) private var healthKitEnabled = true
    @AppStorage(AppConstants.UserDefaultsKeys.notificationsEnabled) private var notificationsEnabled = false
    @AppStorage(AppConstants.UserDefaultsKeys.smartRemindersEnabled) private var smartRemindersEnabled = false
    @Environment(HealthKitAuthorization.self) private var healthAuthorization
    @Environment(StepTrackingService.self) private var trackingService
    @Environment(HealthKitSyncService.self) private var healthKitSyncService
    @Environment(DemoModeStore.self) private var demoModeStore
    @Environment(NotificationService.self) private var notificationService
    @Environment(SmartNotificationService.self) private var smartNotificationService
    @Environment(FoundationModelsService.self) private var aiService
    @Environment(\.presentationMode) private var presentationMode
    private let appVersion = AppVersion()
    @State private var showGoalEditor = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showNotificationAlert = false
    @State private var notificationAlertMessage = ""
    @State private var notificationAlertOffersSettings = false
    @State private var isUpdatingNotifications = false
    @State private var isUpdatingSmartReminders = false
    @State private var showHealthHelp = false

    private var activityMode: ActivityTrackingMode {
        get { ActivityTrackingMode(rawValue: activityModeRaw) ?? .steps }
        nonmutating set { activityModeRaw = newValue.rawValue }
    }

    private var distanceMode: DistanceEstimationMode {
        get { DistanceEstimationMode(rawValue: distanceModeRaw) ?? .automatic }
        nonmutating set { distanceModeRaw = newValue.rawValue }
    }

    private var useFakeDataBinding: Binding<Bool> {
        Binding(
            get: { demoModeStore.useFakeData },
            set: { demoModeStore.useFakeData = $0 }
        )
    }

    private var showsCustomBackButton: Bool {
        presentationMode.wrappedValue.isPresented && LaunchConfiguration.isUITesting()
    }

    var body: some View {
        List {
            goalsSection
            activityTrackingSection
            distanceEstimationSection
            permissionsSection
            aboutSection
            #if DEBUG
            debugSection
            #endif
        }
        .accessibilityIdentifier(A11yID.Settings.list)
        .uiTestMarker(A11yID.Settings.marker)
        .navigationTitle(L10n.localized("Settings", comment: "Settings navigation title"))
        .navigationBarBackButtonHidden(showsCustomBackButton)
        .toolbar {
            if showsCustomBackButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Label(L10n.localized("Back", comment: "Back button label"), systemImage: "chevron.backward")
                    }
                    .accessibilityIdentifier("settings_back_button")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DesignTokens.Colors.surfaceGrouped)
        .task {
            await refreshNotificationStatus()
            await healthAuthorization.refreshStatus()
        }
        .sheet(isPresented: $showGoalEditor) {
            GoalEditorSheet(
                initialGoal: trackingService.currentGoal,
                unitName: activityMode.unitName
            ) { updatedGoal in
                Task { await trackingService.updateGoalAndRefresh(updatedGoal) }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showHealthHelp) {
            HealthAccessHelpSheet()
        }
        .alert(L10n.localized("Notifications", comment: "Alert title for notification settings"), isPresented: $showNotificationAlert) {
            if notificationAlertOffersSettings {
                Button(L10n.localized("Open Settings", comment: "Button to open system settings")) {
                    openNotificationSettings()
                }
            }
            Button(L10n.localized("OK", comment: "Dismiss alert button"), role: .cancel) {}
        } message: {
            Text(notificationAlertMessage)
        }
    }

    private var goalsSection: some View {
        Section {
            Button {
                HapticService.shared.tap()
                showGoalEditor = true
            } label: {
                HStack {
                    Label(L10n.localized("Daily Goal"), systemImage: activityMode.iconName)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Spacer()
                    Text("\(trackingService.currentGoal.formatted()) \(activityMode.unitName)")
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            .accessibleButton(
                label: Localization.format(
                    "Daily Goal: %lld %@",
                    comment: "Accessibility label showing daily goal and unit",
                    Int64(trackingService.currentGoal),
                    activityMode.unitName
                ),
                hint: L10n.localized("Tap to change your daily goal")
            )
            .accessibilityIdentifier(A11yID.Settings.dailyGoalRow)
        } header: {
            Text(L10n.localized("Goals", comment: "Settings section header"))
        }
        .listSectionSpacing(DesignTokens.Spacing.sm)
    }

    private var activityTrackingSection: some View {
        Section {
            ForEach(ActivityTrackingMode.allCases, id: \.self) { mode in
                Button {
                    guard activityMode != mode else { return }
                    HapticService.shared.selection()
                    activityModeRaw = mode.rawValue
                    Task { await trackingService.applySettingsChange() }
                } label: {
                    HStack {
                        Image(systemName: mode.iconName)
                            .font(DesignTokens.Typography.title2)
                            .foregroundStyle(activityMode == mode ? DesignTokens.Colors.accent : DesignTokens.Colors.textSecondary)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                            Text(mode.localizedName)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                            Text(mode.localizedDescription)
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                        Spacer()
                        if activityMode == mode {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DesignTokens.Colors.accent)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.localizedName)
                .accessibilityHint(mode.localizedDescription)
                .accessibilityAddTraits(activityMode == mode ? .isSelected : [])
            }
        } header: {
            Text(L10n.localized("Activity Tracking", comment: "Settings section header for activity tracking"))
        } footer: {
            Text(L10n.localized("Wheelchair mode uses Apple Watch to measure daily pushes instead of steps.", comment: "Settings footer describing wheelchair mode"))
        }
        .listSectionSpacing(DesignTokens.Spacing.sm)
    }

    private var distanceEstimationSection: some View {
        Section {
            ForEach(DistanceEstimationMode.allCases, id: \.self) { mode in
                Button {
                    guard distanceMode != mode else { return }
                    HapticService.shared.selection()
                    distanceModeRaw = mode.rawValue
                    Task { await trackingService.applySettingsChange() }
                } label: {
                    HStack {
                        Image(systemName: mode == .automatic ? "waveform.path.ecg" : "ruler")
                            .font(DesignTokens.Typography.title2)
                            .foregroundStyle(distanceMode == mode ? DesignTokens.Colors.accent : DesignTokens.Colors.textSecondary)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                            Text(mode.localizedName)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                            if mode == .automatic {
                                Text(mode.localizedDescription)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                        }
                        Spacer()
                        if distanceMode == mode {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DesignTokens.Colors.accent)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.localizedName)
                .accessibilityAddTraits(distanceMode == mode ? .isSelected : [])
            }

            if distanceMode == .manual {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack {
                        Text(L10n.localized("Step Length", comment: "Settings label for step length"))
                        Spacer()
                        Text(Formatters.stepLengthString(meters: manualStepLength))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: $manualStepLength,
                        in: 0.4...1.2,
                        step: 0.01,
                        onEditingChanged: { isEditing in
                            guard !isEditing else { return }
                            Task { await trackingService.applySettingsChange() }
                        }
                    )
                        .tint(DesignTokens.Colors.accent)
                        .onChange(of: manualStepLength) {
                            HapticService.shared.selection()
                        }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Localization.format(
                        "Step length: %@",
                        comment: "Accessibility label for manual step length",
                        Formatters.stepLengthString(meters: manualStepLength)
                    )
                )
            }
        } header: {
            Text(L10n.localized("Distance Estimation", comment: "Settings section header for distance estimation"))
        } footer: {
            if distanceMode == .automatic {
                Text(L10n.localized("Uses HealthKit data for more accurate distance tracking.", comment: "Settings footer when distance estimation is automatic"))
            } else {
                Text(L10n.localized("Distance is calculated by multiplying your step count by your step length.", comment: "Settings footer when distance estimation is manual"))
            }
        }
        .listSectionSpacing(DesignTokens.Spacing.sm)
    }

    private var permissionsSection: some View {
        Section {
            Toggle(isOn: $notificationsEnabled) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Label(L10n.localized("Daily Goal Reminder", comment: "Settings toggle for daily reminder"), systemImage: "bell.fill")
                        .symbolRenderingMode(.multicolor)
                    Text(L10n.localized("Get a daily reminder to reach your step goal.", comment: "Daily reminder description"))
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            .disabled(isUpdatingNotifications)
            .onChange(of: notificationsEnabled) { _, newValue in
                HapticService.shared.selection()
                Task { await updateDailyReminder(enabled: newValue) }
            }
            .accessibilityLabel(L10n.localized("Daily Goal Reminder", comment: "Settings toggle for daily reminder"))
            .accessibilityValue(notificationsEnabled ? L10n.localized("Enabled", comment: "Accessibility value for enabled toggle") : L10n.localized("Disabled", comment: "Accessibility value for disabled toggle"))

            smartRemindersRow

            Button {
                showHealthHelp = true
            } label: {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    HStack {
                        Label(L10n.localized("Health Access", comment: "Settings row label for HealthKit access"), systemImage: "heart.text.square")
                            .foregroundStyle(DesignTokens.Colors.accent)
                        Spacer()
                        Text(healthAccessStatusText)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                    if let detail = healthAccessDetailText {
                        Text(detail)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }
            }
            .accessibilityLabel(L10n.localized("Health Access", comment: "Settings row label for HealthKit access"))
            .accessibilityValue(healthAccessStatusText)
            .accessibilityIdentifier(A11yID.Settings.healthAccessRow)

            Toggle(isOn: $healthKitEnabled) {
                Label(L10n.localized("HealthKit Sync", comment: "Settings toggle for HealthKit synchronization"), systemImage: "heart.fill")
                    .foregroundStyle(.pink)
            }
            .onChange(of: healthKitEnabled) {
                HapticService.shared.selection()
                Loggers.sync.info(
                    "sync.toggle_updated",
                    metadata: ["enabled": "\(healthKitEnabled)"]
                )
                guard healthKitEnabled else {
                    Task {
                        _ = await trackingService.refreshWeeklySummaries()
                        await healthAuthorization.refreshStatus()
                    }
                    return
                }
                Task {
                    do {
                        if healthKitSyncService.needsColdStartSync() {
                            try await healthKitSyncService.performColdStartSync()
                        } else {
                            try await healthKitSyncService.performPullToRefresh()
                        }
                        await healthAuthorization.refreshStatus()
                    } catch {
                        Loggers.sync.error("sync.manual_trigger_failed", metadata: [
                            "error": error.localizedDescription
                        ])
                    }
                }
            }
            .accessibilityIdentifier(A11yID.Settings.healthKitSyncToggle)
            .accessibilityLabel(L10n.localized("HealthKit Sync", comment: "Settings toggle for HealthKit synchronization"))
            .applyIfNotUITesting {
                $0.accessibilityValue(
                    healthKitEnabled
                        ? L10n.localized("Enabled", comment: "Accessibility value for enabled toggle")
                        : L10n.localized("Disabled", comment: "Accessibility value for disabled toggle")
                )
            }
        } header: {
            Text(L10n.localized("Permissions", comment: "Settings section header"))
        }
        .listSectionSpacing(DesignTokens.Spacing.sm)
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutView()
            } label: {
                HStack {
                    Label(L10n.localized("About", comment: "Settings row that opens About screen"), systemImage: "info.circle")
                    Spacer()
                    Text(appVersion.display)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            .accessibilityIdentifier(A11yID.Settings.aboutRow)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.localized("About", comment: "Settings row that opens About screen"))
            .accessibilityValue(appVersion.display)
        } header: {
            Text(L10n.localized("About", comment: "Settings section header"))
        }
        .listSectionSpacing(DesignTokens.Spacing.sm)
    }

    @ViewBuilder
    private var debugSection: some View {
        #if DEBUG
        Section {
            NavigationLink {
                HealthKitDebugView()
            } label: {
                Label("Debug do HealthKit", systemImage: "heart.text.square")
            }

            Toggle(isOn: useFakeDataBinding) {
                HStack {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .foregroundStyle(DesignTokens.Colors.warning)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(L10n.localized("Use Fake Data", comment: "Debug toggle for synthetic HealthKit data"))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                        Text(L10n.localized("Synthetic HealthKit data", comment: "Fake data toggle description"))
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }
            }
            .accessibilityIdentifier(A11yID.Settings.demoFakeDataToggle)
            .onChange(of: demoModeStore.useFakeData) { _, _ in
                HapticService.shared.selection()
            }

            Button(role: .destructive) {
                HapticService.shared.error()
                onboardingCompleted = false
            } label: {
                Label(L10n.localized("Reset Onboarding", comment: "Debug button to reset onboarding state"), systemImage: "arrow.counterclockwise")
            }
            .accessibleButton(label: L10n.localized("Reset Onboarding", comment: "Debug button to reset onboarding state"), hint: L10n.localized("Resets the app to show onboarding again", comment: "Accessibility hint for reset onboarding button"))
        } header: {
            Text(L10n.localized("Debug", comment: "Settings section header for debug options"))
        } footer: {
            Text(L10n.localized("Fake Data uses synthetic HealthKit data for testing.", comment: "Debug section footer explaining demo options"))
        }
        .listSectionSpacing(DesignTokens.Spacing.sm)
        #else
        EmptyView()
        #endif
    }

    private var smartRemindersRow: some View {
        Group {
            Toggle(isOn: $smartRemindersEnabled) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Label(L10n.localized("Smart Reminders", comment: "Settings toggle for AI reminders"), systemImage: "sparkles")
                        .foregroundStyle(DesignTokens.Colors.accent)
                    Text(L10n.localized("AI-generated reminders based on your progress.", comment: "Smart reminders description"))
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            .disabled(isUpdatingSmartReminders || !aiService.availability.isAvailable)
            .onChange(of: smartRemindersEnabled) { _, newValue in
                HapticService.shared.selection()
                Task { await updateSmartReminders(enabled: newValue) }
            }
            .accessibilityLabel(L10n.localized("Smart Reminders", comment: "Settings toggle for AI reminders"))
            .accessibilityValue(smartRemindersEnabled ? L10n.localized("Enabled", comment: "Accessibility value for enabled toggle") : L10n.localized("Disabled", comment: "Accessibility value for disabled toggle"))
            if case .unavailable(let reason) = aiService.availability {
                Text(reason.userFacingMessage)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
    }

    private var healthAccessStatusText: String {
        switch healthAuthorization.status {
        case .shouldRequest:
            return L10n.localized("Not Requested", comment: "Health access status when not requested")
        case .requested:
            return L10n.localized("Requested", comment: "Health access status when authorization was requested")
        case .unavailable:
            return L10n.localized("Unavailable", comment: "Health access status when unavailable")
        }
    }

    private var healthAccessDetailText: String? {
        switch healthAuthorization.status {
        case .shouldRequest:
            return L10n.localized("Tap to allow Health access.", comment: "Health access detail when not requested")
        case .requested:
            return String(
                localized: "Health access was already requested. If data isn't showing, enable it in Settings.",
                comment: "HealthKit authorization guidance after requesting"
            )
        case .unavailable:
            return String(
                localized: "Health data is not available on this device.",
                comment: "HealthKit not available error"
            )
        }
    }

    private var isNotificationAuthorized: Bool {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    private func refreshNotificationStatus() async {
        let status = await notificationService.authorizationStatus()
        notificationStatus = status

        guard isNotificationAuthorized else {
            if notificationsEnabled {
                notificationService.cancelDailyGoalReminder()
            }
            if smartRemindersEnabled {
                smartNotificationService.cancelAllSmartNotifications()
            }
            notificationsEnabled = false
            smartRemindersEnabled = false
            return
        }
    }

    private func updateDailyReminder(enabled: Bool) async {
        isUpdatingNotifications = true
        defer { isUpdatingNotifications = false }

        if enabled {
            guard await ensureNotificationAuthorization() else {
                notificationsEnabled = false
                return
            }
            do {
                try await notificationService.scheduleDailyGoalReminder(
                    hour: AppConstants.Notifications.defaultDailyReminderHour,
                    minute: AppConstants.Notifications.defaultDailyReminderMinute
                )
                Loggers.app.info("notifications.daily_goal_enabled")
            } catch {
                notificationsEnabled = false
                showNotificationAlert(
                    message: L10n.localized("Unable to schedule notifications. Please try again.", comment: "Alert when scheduling notifications fails"),
                    offersSettings: false
                )
                Loggers.app.error("notifications.daily_goal_failed", metadata: ["error": error.localizedDescription])
            }
        } else {
            notificationService.cancelDailyGoalReminder()
            Loggers.app.info("notifications.daily_goal_disabled")
        }
    }

    private func updateSmartReminders(enabled: Bool) async {
        isUpdatingSmartReminders = true
        defer { isUpdatingSmartReminders = false }

        guard aiService.availability.isAvailable else {
            smartRemindersEnabled = false
            if case .unavailable(let reason) = aiService.availability {
                showNotificationAlert(message: reason.userFacingMessage, offersSettings: false)
            }
            return
        }

        if enabled {
            guard await ensureNotificationAuthorization() else {
                smartRemindersEnabled = false
                return
            }
            await smartNotificationService.scheduleMotivationalReminder(
                at: AppConstants.Notifications.defaultSmartReminderHour,
                minute: AppConstants.Notifications.defaultSmartReminderMinute
            )
            Loggers.ai.info("notifications.smart_enabled")
        } else {
            smartNotificationService.cancelAllSmartNotifications()
            Loggers.ai.info("notifications.smart_disabled")
        }
    }

    private func ensureNotificationAuthorization() async -> Bool {
        let status = await notificationService.authorizationStatus()
        notificationStatus = status

        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                let granted = try await notificationService.requestAuthorization()
                let updatedStatus = await notificationService.authorizationStatus()
                notificationStatus = updatedStatus
                if granted {
                    return true
                }
            } catch {
                showNotificationAlert(
                    message: L10n.localized("Unable to request notification permissions.", comment: "Alert when notification permission request fails"),
                    offersSettings: false
                )
                return false
            }
            showNotificationAlert(
                message: L10n.localized("Notifications are disabled. Enable them in Settings.", comment: "Alert message when notifications are denied"),
                offersSettings: true
            )
            return false
        case .denied:
            showNotificationAlert(
                message: L10n.localized("Notifications are disabled. Enable them in Settings.", comment: "Alert message when notifications are denied"),
                offersSettings: true
            )
            return false
        @unknown default:
            return false
        }
    }

    private func showNotificationAlert(message: String, offersSettings: Bool) {
        notificationAlertMessage = message
        notificationAlertOffersSettings = offersSettings
        showNotificationAlert = true
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct GoalEditorSheet: View {
    let initialGoal: Int
    let unitName: String
    let onSave: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tempGoal: Double

    init(initialGoal: Int, unitName: String, onSave: @escaping (Int) -> Void) {
        self.initialGoal = initialGoal
        self.unitName = unitName
        self.onSave = onSave
        _tempGoal = State(initialValue: Double(initialGoal))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.xl) {
                Spacer()

                Text("\(Int(tempGoal).formatted())")
                    .font(.system(size: DesignTokens.FontSize.xl, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityIdentifier(A11yID.GoalEditor.value)

                Text(
                    Localization.format(
                        "%@ per day",
                        comment: "Label in goal editor showing unit per day",
                        unitName
                    )
                )
                    .font(DesignTokens.Typography.title3)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                Slider(value: $tempGoal, in: 1000...30000, step: 500)
                    .padding(.horizontal, DesignTokens.Spacing.xl)
                    .tint(DesignTokens.Colors.accent)
                    .accessibilityIdentifier(A11yID.GoalEditor.slider)
                    .accessibilityLabel(L10n.localized("Daily step goal", comment: "Accessibility label for step goal slider"))
                    .accessibilityValue(
                        Localization.format(
                            "%lld %@",
                            comment: "Accessibility value showing current goal and unit",
                            Int64(tempGoal),
                            unitName
                        )
                    )

                Spacer()
            }
            .navigationTitle(L10n.localized("Daily Goal", comment: "Goal editor navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.localized("Cancel", comment: "Button to cancel action")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("goal_editor_cancel_button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.localized("Save", comment: "Button to save changes")) {
                        HapticService.shared.confirm()
                        onSave(Int(tempGoal))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier(A11yID.GoalEditor.saveButton)
                }
            }
        }
    }
}

#Preview {
    @MainActor in
    let persistence = PersistenceController.shared
    let goalService = GoalService(persistence: persistence)
    let streakCalculator = StreakCalculator(stepAggregator: StepDataAggregator(), goalService: goalService)
    let badgeService = BadgeService(persistence: persistence)
    let demoModeStore = DemoModeStore()
    let healthAuthorization = HealthKitAuthorization()
    return SettingsView()
        .environment(StepTrackingService(
            healthKitService: HealthKitService(),
            motionService: MotionService(),
            healthAuthorization: healthAuthorization,
            goalService: goalService,
            badgeService: badgeService,
            dataStore: SharedDataStore(),
            streakCalculator: streakCalculator
        ))
        .environment(healthAuthorization)
        .environment(demoModeStore)
}

#Preview("Goal Editor") {
    GoalEditorSheet(initialGoal: 10000, unitName: ActivityTrackingMode.steps.unitName) { _ in }
}
