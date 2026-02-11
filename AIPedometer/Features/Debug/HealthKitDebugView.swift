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
        .navigationTitle("Debug do HealthKit")
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
                .accessibilityLabel("Atualizar")
            }
        }
        .task {
            await refresh()
        }
        .alert(
            "Debug do HealthKit",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented { errorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var summarySection: some View {
        Section {
            if days.isEmpty {
                Text(isLoading ? "Carregando..." : "Sem dados ainda.")
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            } else {
                let sumAll = days.reduce(0) { $0 + $1.totalAllSources }
                let sumApple = days.reduce(0) { $0 + $1.totalAppleSources }
                let sumUsed = days.reduce(0) { $0 + $1.totalUsedByApp }

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    row("Total (todas as fontes)", value: sumAll)
                    row("Total (fontes Apple)", value: sumApple)
                    row("Total (usado no app)", value: sumUsed)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Resumo do HealthKit dos ultimos 7 dias")

                Text("O app usa o total agregado do HealthKit (HKStatisticsQuery/Collection) que aplica a logica do proprio iOS para mesclar dados entre dispositivos e respeitar a prioridade de fontes configurada em Saude. Os totais por fonte aqui sao diagnostico: somar fontes pode inflar o total por haver sobreposicao (mesmas caminhadas contadas por multiplos dispositivos).")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        } header: {
            Text("Resumo (7 dias)")
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
                        smallPill("Todas", value: day.totalAllSources)
                        smallPill("Apple", value: day.totalAppleSources)
                        smallPill("App", value: day.totalUsedByApp)
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
                            Text("... +\(day.sources.count - 6) fontes")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
        } header: {
            Text("Por dia")
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
            errorMessage = "HealthKit nao esta disponivel neste dispositivo."
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
