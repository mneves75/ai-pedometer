import SwiftUI

struct HealthAccessHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitAuthorization.self) private var healthAuthorization
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isRequesting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    Text(
                        String(
                            localized: "To show history and Apple Watch data, AI Pedometer needs Health read access.",
                            comment: "Health access help intro"
                        )
                    )
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                    if healthAuthorization.status == .shouldRequest {
                        Button(L10n.localized("Grant Access", comment: "Button to request Health access")) {
                            Task { await requestAccess() }
                        }
                        .glassButton()
                        .disabled(isRequesting)
                        .accessibilityIdentifier(A11yID.HealthAccessHelp.grantAccessButton)
                    }

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        Text(L10n.localized("How to enable", comment: "Health access help section title"))
                            .font(DesignTokens.Typography.headline)

                        instructionRow(
                            number: 1,
                            text: String(
                                localized: "Open the Health app.",
                                comment: "Health access help step 1"
                            )
                        )
                        instructionRow(
                            number: 2,
                            text: String(
                                localized: "Go to Sharing, then Apps.",
                                comment: "Health access help step 2"
                            )
                        )
                        instructionRow(
                            number: 3,
                            text: String(
                                localized: "Select AI Pedometer and allow access to Steps and Activity.",
                                comment: "Health access help step 3"
                            )
                        )
                        instructionRow(
                            number: 4,
                            text: String(
                                localized: "Return to AI Pedometer and refresh the Dashboard/History.",
                                comment: "Health access help step 4"
                            )
                        )

                        Text(
                            String(
                                localized: "If you prefer: Settings > Health > Data Access & Devices > AI Pedometer.",
                                comment: "Health access help alternative path"
                            )
                        )
                        .font(DesignTokens.Typography.subheadline)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .padding(.top, DesignTokens.Spacing.sm)
                    }
                    .glassCard(cornerRadius: DesignTokens.CornerRadius.xl, interactive: false)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        Text(
                            String(
                                localized: "Data sources (priority)",
                                comment: "Health access help section title about Health data sources ordering"
                            )
                        )
                            .font(DesignTokens.Typography.headline)

                        Text(
                            String(
                                localized: "Health can have multiple step sources (Apple Watch, iPhone, and third-party apps/devices). Their order affects what you see as the primary value.",
                                comment: "Health access help section description about multi-source step data"
                            )
                        )
                        .font(DesignTokens.Typography.subheadline)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)

                        instructionRow(number: 1, text: L10n.localized("Open the Health app.", comment: "Health data sources help step 1"))
                        instructionRow(number: 2, text: L10n.localized("Go to Browse > Activity > Steps.", comment: "Health data sources help step 2"))
                        instructionRow(number: 3, text: L10n.localized("Scroll down to “Data Sources & Access” and tap Edit.", comment: "Health data sources help step 3"))
                        instructionRow(number: 4, text: L10n.localized("Keep the source you want to prioritize at the top (e.g., Apple Watch).", comment: "Health data sources help step 4"))

                        Text(
                            String(
                                localized: "Tip: if AI Pedometer History is empty or lower than expected, verify steps are being saved to Health and your primary source isn't a third-party app without permission.",
                                comment: "Health data sources help tip"
                            )
                        )
                        .font(DesignTokens.Typography.subheadline)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .padding(.top, DesignTokens.Spacing.sm)
                    }
                    .glassCard(cornerRadius: DesignTokens.CornerRadius.xl, interactive: false)
                }
                .padding(DesignTokens.Spacing.lg)
            }
            .accessibilityIdentifier(A11yID.HealthAccessHelp.view)
            .navigationTitle(L10n.localized("Health Access", comment: "Title for health access help sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.localized("Done", comment: "Dismiss health access help sheet button")) {
                        dismiss()
                    }
                    .accessibilityIdentifier(A11yID.HealthAccessHelp.doneButton)
                }
            }
        }
        .alert(L10n.localized("Health Access", comment: "Alert title for HealthKit access"), isPresented: $showError) {
            Button(L10n.localized("OK", comment: "Dismiss alert button"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            Text("\(number).")
                .font(DesignTokens.Typography.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func requestAccess() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }

        do {
            try await healthAuthorization.requestAuthorization()
            await healthAuthorization.refreshStatus()
        } catch {
            errorMessage = (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    HealthAccessHelpSheet()
}
