import HealthKit
import SwiftUI

#if DEBUG
@MainActor
struct HealthKitDebugView: View {
    private struct SourceSteps: Identifiable {
        let id: String
        let name: String
        let bundleIdentifier: String
        let steps: Int
        let isApple: Bool
    }

    private struct DayDebug: Identifiable {
        let id: Date
        let date: Date
        let totalAllSources: Int
        let totalAppleSources: Int
        let totalUsedByApp: Int
        let sources: [SourceSteps]
    }

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var days: [DayDebug] = []

    private let calendar = Calendar.autoupdatingCurrent
    private let calculator = DailyStepCalculator()
    private let healthStore = HKHealthStore()

    var body: some View {
        List {
            summarySection
            dayBreakdownSection
        }
        .navigationTitle(L10n.localized("Debug do HealthKit", comment: "A title for this view."))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
                .accessibilityLabel(L10n.localized("Atualizar", comment: "Refresh debug data button"))
            }
        }
        .task {
            await refresh()
        }
        .alert(
            L10n.localized("Debug do HealthKit", comment: "A title for this view."),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented { errorMessage = nil }
                }
            )
        ) {
            Button(L10n.localized("OK", comment: "Dismiss alert button"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var summarySection: some View {
        Section {
            if days.isEmpty {
                Text(isLoading
                     ? L10n.localized("Carregando...", comment: "Loading state")
                     : L10n.localized("Sem dados ainda.", comment: "No data empty state"))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            } else {
                let sumAll = days.reduce(0) { $0 + $1.totalAllSources }
                let sumApple = days.reduce(0) { $0 + $1.totalAppleSources }
                let sumUsed = days.reduce(0) { $0 + $1.totalUsedByApp }

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    row(L10n.localized("Total (all sources)", comment: "HealthKit debug total for all sources"), value: sumAll)
                    row(L10n.localized("Total (Apple sources)", comment: "HealthKit debug total for Apple sources"), value: sumApple)
                    row(L10n.localized("Total (used by app)", comment: "HealthKit debug total used by the app"), value: sumUsed)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L10n.localized(
                    "Resumo do HealthKit dos ultimos 7 dias",
                    comment: "HealthKit debug summary accessibility label"
                ))

                Text(L10n.localized(
                    "O app usa o total agregado do HealthKit (HKStatisticsQuery/Collection) que aplica a logica do proprio iOS para mesclar dados entre dispositivos e respeitar a prioridade de fontes configurada em Saude. Os totais por fonte aqui sao diagnostico: somar fontes pode inflar o total por haver sobreposicao (mesmas caminhadas contadas por multiplos dispositivos).",
                    comment: "HealthKit debug explanation"
                ))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        } header: {
            Text(L10n.localized("Resumo (7 dias)", comment: "HealthKit debug section header"))
        }
    }

    private var dayBreakdownSection: some View {
        Section {
            ForEach(days.sorted(by: { $0.date > $1.date })) { day in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack {
                        Text(day.date.formatted(date: .abbreviated, time: .omitted))
                            .font(DesignTokens.Typography.headline)
                        Spacer()
                        Text("\(day.totalUsedByApp.formatted())")
                            .font(DesignTokens.Typography.headline)
                            .monospacedDigit()
                    }

                    HStack(spacing: DesignTokens.Spacing.md) {
                        smallPill(L10n.localized("All", comment: "HealthKit debug all sources pill"), value: day.totalAllSources)
                        smallPill(L10n.localized("Apple", comment: "HealthKit debug Apple sources pill"), value: day.totalAppleSources)
                        smallPill(L10n.localized("App", comment: "HealthKit debug app aggregate pill"), value: day.totalUsedByApp)
                    }

                    if !day.sources.isEmpty {
                        Divider()
                        ForEach(day.sources.prefix(6)) { source in
                            HStack {
                                Text(source.name)
                                    .font(DesignTokens.Typography.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Text(source.steps.formatted())
                                    .font(DesignTokens.Typography.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(source.isApple ? DesignTokens.Colors.success : DesignTokens.Colors.textSecondary)
                            }
                        }
                        if day.sources.count > 6 {
                            Text(Localization.format(
                                "... +%d sources",
                                comment: "HealthKit debug hidden source count",
                                day.sources.count - 6
                            ))
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
        } header: {
            Text(L10n.localized("Por dia", comment: "HealthKit debug section header by day"))
        }
    }

    private func row(_ title: String, value: Int) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Spacer()
            Text(value.formatted())
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .monospacedDigit()
        }
    }

    private func smallPill(_ title: String, value: Int) -> some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Text(title)
                .font(DesignTokens.Typography.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text(value.formatted())
                .font(DesignTokens.Typography.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
    }

    private func refresh() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = HealthKitError.notAvailable.localizedDescription
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            try await requestAuthorizationIfNeeded()
            days = try await fetchLast7Days()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestAuthorizationIfNeeded() async throws {
        // Requesting again is safe (HealthKit will short-circuit if already authorized).
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.stepCount)
        ]
        try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
    }

    private func fetchLast7Days() async throws -> [DayDebug] {
        let aggregator = StepDataAggregator(healthStore: healthStore)
        let healthKitService = HealthKitService(healthStore: healthStore, calendar: calendar)

        let ranges = calculator.dailyRanges(days: 7, endingOn: .now)
        var result: [DayDebug] = []
        result.reserveCapacity(ranges.count)

        for range in ranges {
            let perSource = try await aggregator.fetchStepsBySource(from: range.start, to: range.end)
            let totalUsed = try await healthKitService.fetchSteps(from: range.start, to: range.end)

            let sources: [SourceSteps] = perSource
                .map { (source, steps) in
                    let bundle = source.bundleIdentifier
                    let apple = bundle.lowercased().hasPrefix("com.apple.")
                    return SourceSteps(
                        id: "\(bundle)|\(source.name)",
                        name: source.name,
                        bundleIdentifier: bundle,
                        steps: steps,
                        isApple: apple
                    )
                }
                .sorted { $0.steps > $1.steps }

            let totalAll = sources.reduce(0) { $0 + $1.steps }
            let totalApple = sources.filter(\.isApple).reduce(0) { $0 + $1.steps }

            result.append(
                DayDebug(
                    id: range.start,
                    date: range.start,
                    totalAllSources: totalAll,
                    totalAppleSources: totalApple,
                    totalUsedByApp: totalUsed,
                    sources: sources
                )
            )
        }

        return result
    }
}
#endif
