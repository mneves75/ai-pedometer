import SwiftUI

enum AICoachBottomPinningPolicy {
    static let tolerance: CGFloat = 24

    static func isBottomVisible(
        contentOffsetY: CGFloat,
        contentHeight: CGFloat,
        containerHeight: CGFloat,
        bottomInset: CGFloat,
        tolerance: CGFloat = tolerance
    ) -> Bool {
        let visibleBottom = contentOffsetY + containerHeight
        let contentBottom = contentHeight + bottomInset
        return visibleBottom >= contentBottom - tolerance
    }

    static func updatedPinning(
        currentPinning: Bool,
        isBottomVisible: Bool,
        isUserScrollActive: Bool
    ) -> Bool {
        guard isUserScrollActive else { return currentPinning }
        return isBottomVisible
    }
}

struct AICoachView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(CoachService.self) private var coachService
    @Environment(FoundationModelsService.self) private var aiService
    @Environment(PremiumAccessStore.self) private var premiumAccessStore
    @Environment(\.openURL) private var openExternalURL

    private let autoScrollMinInterval: TimeInterval = DesignTokens.Animation.defaultDuration
    @State private var inputText = ""
    @State private var isPinnedToBottom = true
    @State private var isUserScrollActive = false
    @State private var linkConfirmation = AIChatLinkConfirmation()
    @State private var lastAutoScrollTime = Date.distantPast
    @State private var showClearConfirmation = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        coachContent
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(A11yID.AICoach.view)
            .background(DesignTokens.Colors.surfaceGrouped)
            .navigationTitle(L10n.localized("AI Coach", comment: "AI Coach navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            // Model-generated links must pass policy and explicit user confirmation.
            .environment(\.openURL, OpenURLAction { url in
                guard linkConfirmation.request(url) else { return .discarded }
                return .handled
            })
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !coachService.messages.isEmpty {
                        Button(L10n.localized("Clear", comment: "Clear conversation button")) {
                            showClearConfirmation = true
                        }
                        .font(DesignTokens.Typography.subheadline)
                    }
                }
            }
            .confirmationDialog(
                L10n.localized("Clear conversation?", comment: "AI Coach clear conversation confirmation title"),
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button(L10n.localized("Clear", comment: "Clear conversation button"), role: .destructive) {
                    coachService.clearConversation()
                }
                Button(L10n.localized("Cancel", comment: "Cancel button"), role: .cancel) {}
            } message: {
                Text(L10n.localized("This removes the current AI Coach conversation from this device.", comment: "AI Coach clear conversation confirmation message"))
            }
            .alert(
                L10n.localized("Open external link?", comment: "AI Coach external link confirmation title"),
                isPresented: Binding(
                    get: { linkConfirmation.pendingLink != nil },
                    set: { isPresented in
                        if !isPresented {
                            linkConfirmation.cancel()
                        }
                    }
                ),
                presenting: linkConfirmation.pendingLink
            ) { _ in
                Button(L10n.localized("Cancel", comment: "Cancel button"), role: .cancel) {
                    linkConfirmation.cancel()
                }
                Button(L10n.localized("Open Link", comment: "AI Coach external link confirmation button")) {
                    guard let confirmedURL = linkConfirmation.confirm() else { return }
                    openExternalURL(confirmedURL)
                }
            } message: { pendingLink in
                Text(
                    Localization.format(
                        "Host: %@\n\nFull URL: %@",
                        comment: "AI Coach external link confirmation details",
                        pendingLink.host,
                        pendingLink.url.absoluteString
                    )
                )
            }
    }

    private var coachContent: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            if premiumAccessStore.isResolvingAccess {
                PremiumAccessLoadingCard(
                    title: L10n.localized("AI Coach", comment: "AI Coach navigation title")
                )
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.xl)
                Spacer(minLength: DesignTokens.Spacing.xl)
            } else if !premiumAccessStore.canAccessAIFeatures {
                PremiumFeatureGateCard(
                    title: L10n.localized("AI Coach", comment: "AI Coach navigation title"),
                    message: L10n.localized(
                        "Premium is required to generate new AI insights, coaching, plans, and smart reminders.",
                        comment: "Premium gate copy for AI features"
                    )
                )
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.xl)
                Spacer(minLength: DesignTokens.Spacing.xl)
            } else if case .unavailable(let reason) = aiService.availability {
                AIUnavailableStateView(reason: reason)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.xl)
                Spacer(minLength: DesignTokens.Spacing.xl)
            } else {
                messagesScrollView
                disclaimerText
                inputSection
            }
        }
        .uiTestMarker(A11yID.AICoach.marker)
    }

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.md) {
                    if coachService.messages.isEmpty && aiService.availability.isAvailable {
                        welcomeSection
                    }

                    ForEach(coachService.messages) { message in
                        ChatMessageView(message: message)
                            .id(message.id)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .move(edge: .bottom).combined(with: .opacity)
                            )
                    }

                    if coachService.isGenerating {
                        streamingMessageView
                            .id("streaming")
                    }

                    if let error = coachService.lastError, shouldShowErrorBanner(for: error) {
                        errorBanner(error)
                    }
                }
                .padding(DesignTokens.Spacing.md)
                .animation(reduceMotion ? nil : DesignTokens.Animation.smooth, value: coachService.messages.count)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                AICoachBottomPinningPolicy.isBottomVisible(
                    contentOffsetY: geometry.contentOffset.y,
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.containerSize.height,
                    bottomInset: geometry.contentInsets.bottom
                )
            } action: { _, isBottomVisible in
                isPinnedToBottom = AICoachBottomPinningPolicy.updatedPinning(
                    currentPinning: isPinnedToBottom,
                    isBottomVisible: isBottomVisible,
                    isUserScrollActive: isUserScrollActive
                )
            }
            .onScrollPhaseChange { _, newPhase in
                isUserScrollActive = switch newPhase {
                case .tracking, .interacting, .decelerating:
                    true
                case .idle, .animating:
                    false
                }
            }
            .onChange(of: coachService.messages.count) { _, _ in
                guard isPinnedToBottom else { return }
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: coachService.currentStreamedContent) { _, _ in
                guard isPinnedToBottom else { return }
                scrollToBottomThrottled(proxy: proxy)
            }
        }
    }

    private var welcomeSection: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "sparkles")
                .font(.system(size: DesignTokens.FontSize.md))
                .foregroundStyle(DesignTokens.Colors.accent)
                .applyIfMotionEnabled { view in
                    view.symbolEffect(.pulse, options: .repeating.speed(0.5))
                }

            VStack(spacing: DesignTokens.Spacing.sm) {
                Text(L10n.localized("Hi, I'm your AI Coach!", comment: "AI Coach welcome greeting"))
                    .font(DesignTokens.Typography.title2.bold())

                Text(L10n.localized("Ask me anything about your fitness progress, goals, or get personalized recommendations.", comment: "AI Coach welcome description"))
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            suggestedQuestionsSection
        }
        .padding(.vertical, DesignTokens.Spacing.xl)
    }

    private var suggestedQuestionsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(L10n.localized("Try asking:", comment: "Label for suggested questions"))
                .font(DesignTokens.Typography.subheadline.weight(.medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            FlowLayout(spacing: DesignTokens.Spacing.sm) {
                ForEach(coachService.suggestedQuestions, id: \.self) { question in
                    Button {
                        Task { await coachService.send(message: question) }
                    } label: {
                        Text(question)
                            .font(DesignTokens.Typography.subheadline)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.vertical, DesignTokens.Spacing.sm)
                            .frame(minHeight: DesignTokens.TouchTarget.minimum)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var streamingMessageView: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.accent)
                .frame(width: DesignTokens.IconSize.sm, height: DesignTokens.IconSize.sm)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                if coachService.currentStreamedContent.isEmpty {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.localized("Thinking...", comment: "AI Coach thinking state"))
                            .font(DesignTokens.Typography.subheadline)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                } else {
                    if coachService.currentStreamedContent.count <= CoachService.maxLiveMarkdownChars {
                        Text(coachService.currentStreamedRenderedContent)
                    } else {
                        Text(coachService.currentStreamedContent)
                            .font(DesignTokens.Typography.subheadline)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                    }
                }
            }

            Spacer()
        }
        .padding(DesignTokens.Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputSection: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            Divider()

            HStack(spacing: DesignTokens.Spacing.sm) {
                TextField(L10n.localized("Ask your coach...", comment: "AI Coach input placeholder"), text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit(sendMessage)
                    .accessibilityLabel(L10n.localized("Message", comment: "AI Coach message input label"))

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(DesignTokens.Typography.title2)
                        .foregroundStyle(canSend ? DesignTokens.Colors.accent : DesignTokens.Colors.textTertiary)
                }
                .frame(width: DesignTokens.IconSize.touchTarget, height: DesignTokens.IconSize.touchTarget)
                .disabled(!canSend)
                .accessibilityLabel(L10n.localized("Send Message", comment: "AI Coach send button accessibility label"))
                .accessibilityIdentifier("ai_coach_send_button")
            }
            .padding(DesignTokens.Spacing.md)
            .background(.bar)
        }
    }

    private var disclaimerText: some View {
        AIDisclaimerText()
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.sm)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !coachService.isGenerating
    }

    private var canRetryLastMessage: Bool {
        coachService.messages.contains { $0.role == .user }
    }

    private func shouldShowErrorBanner(for error: AIServiceError) -> Bool {
        AICoachErrorPresentationPolicy.shouldShowGlobalErrorBanner(
            lastError: error,
            messages: coachService.messages
        )
    }

    private func errorBanner(_ error: AIServiceError) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Label {
                Text(error.localizedDescription)
                    .font(DesignTokens.Typography.subheadline)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.Colors.warning)
            }

            if canRetryLastMessage && !coachService.isGenerating {
                Button(L10n.localized("Try Again", comment: "Retry button")) {
                    Task { await coachService.retryLastMessage() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))
    }

    private func sendMessage() {
        guard canSend else { return }
        let message = inputText
        inputText = ""
        isPinnedToBottom = true
        lastAutoScrollTime = .distantPast
        Task {
            await coachService.send(message: message)
        }
    }

    private func scrollToBottomThrottled(proxy: ScrollViewProxy) {
        let now = Date()
        guard now.timeIntervalSince(lastAutoScrollTime) >= autoScrollMinInterval else { return }
        lastAutoScrollTime = now
        scrollToBottom(proxy: proxy, animated: false)
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        isPinnedToBottom = true
        if animated {
            withAnimation(reduceMotion ? nil : DesignTokens.Animation.smooth) {
                scrollToBottomTarget(proxy: proxy)
            }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                scrollToBottomTarget(proxy: proxy)
            }
        }
    }

    private func scrollToBottomTarget(proxy: ScrollViewProxy) {
        if coachService.isGenerating {
            proxy.scrollTo("streaming", anchor: .bottom)
        } else if let lastMessage = coachService.messages.last {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}

struct ChatMessageView: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            if isUser { Spacer(minLength: DesignTokens.Sizing.chatBubbleGutter) }

            if !isUser {
                Image(systemName: "sparkles")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.accent)
                    .frame(width: DesignTokens.IconSize.sm, height: DesignTokens.IconSize.sm)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: DesignTokens.Spacing.xxs) {
                Group { messageContent }
                .padding(DesignTokens.Spacing.md)
                .background(
                    isUser ? AnyShapeStyle(DesignTokens.Colors.accent) : AnyShapeStyle(.ultraThinMaterial),
                    in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md)
                )

                if let terminalError = message.terminalError, !isUser {
                    Label {
                        Text(terminalError.partialResponseNotice)
                            .font(DesignTokens.Typography.caption)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(DesignTokens.Colors.warning)
                    .accessibilityIdentifier("ai_coach_partial_message_notice")
                }

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            if !isUser { Spacer(minLength: DesignTokens.Sizing.chatBubbleGutter) }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        if isUser {
            Text(message.content)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.inverseText)
        } else if let rendered = message.renderedContent {
            // Keep assistant styles embedded in AttributedString (links/code spans).
            Text(rendered)
        } else {
            // Fallback if rendering failed or message was produced by an older build.
            Text(message.content)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
    }
}

enum AICoachErrorPresentationPolicy {
    static func shouldShowGlobalErrorBanner(
        lastError: AIServiceError,
        messages: [ChatMessage]
    ) -> Bool {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else {
            return true
        }

        guard let terminalError = lastAssistant.terminalError else {
            return true
        }

        return !isSameErrorKind(terminalError, lastError)
    }

    static func isSameErrorKind(_ lhs: AIServiceError, _ rhs: AIServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.sessionNotConfigured, .sessionNotConfigured):
            return true
        case let (.modelUnavailable(leftReason), .modelUnavailable(rightReason)):
            return leftReason == rightReason
        case (.generationFailed, .generationFailed):
            return true
        case (.tokenLimitExceeded, .tokenLimitExceeded):
            return true
        case (.guardrailViolation, .guardrailViolation):
            return true
        case (.invalidResponse, .invalidResponse):
            return true
        default:
            return false
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        let childProposal = maxWidth.isFinite ? ProposedViewSize(width: maxWidth, height: nil) : .unspecified
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(childProposal)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}

#Preview {
    @MainActor in
    let fmService = FoundationModelsService()
    let demoModeStore = DemoModeStore()
    let healthKitService = HealthKitServiceFallback(demoModeStore: demoModeStore)
    return AICoachView()
        .environment(CoachService(
            foundationModelsService: fmService,
            healthKitService: healthKitService,
            goalService: GoalService(persistence: PersistenceController.shared)
        ))
        .environment(fmService)
        .environment(demoModeStore)
        // AICoachView gates on PremiumAccessStore before rendering chat; injecting a forced-on
        // premium store keeps the preview functional.
        .environment(PremiumAccessStore(forcedPremiumEnabled: true, isTesting: true))
}
