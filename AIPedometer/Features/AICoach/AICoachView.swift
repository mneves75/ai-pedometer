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
            .background {
                AmbientZenithBackground()
            }
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
            if case .unavailable(let reason) = aiService.availability {
                Spacer(minLength: DesignTokens.Spacing.lg)
                AIUnavailableStateView(reason: reason)
                    .padding(.horizontal, DesignTokens.Spacing.mdPlus)
                Spacer(minLength: DesignTokens.Spacing.xl)
            } else {
                messagesScrollView
                composerFooter
            }
        }
        .uiTestMarker(A11yID.AICoach.marker)
        .uiTestMarker(
            A11yID.AICoach.unavailableState,
            when: !aiService.availability.isAvailable
        )
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
                .padding(.horizontal, DesignTokens.Spacing.mdPlus)
                .padding(.vertical, DesignTokens.Spacing.md)
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
        VStack(spacing: DesignTokens.Spacing.xl) {
            VStack(spacing: DesignTokens.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(DesignTokens.Colors.accentSoft)
                        .frame(width: 68, height: 68)
                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.accent)
                }
                .glassCard(cornerRadius: 34)
                .accessibilityHidden(true)

                Text(L10n.localized("Hi, I'm your AI Coach!", comment: "AI Coach welcome greeting"))
                    .font(DesignTokens.Typography.title2.bold())
                    .multilineTextAlignment(.center)
            }

            suggestedQuestionsSection
        }
        .padding(.top, DesignTokens.Spacing.xl)
    }

    private var suggestedQuestionsSection: some View {
        FlowLayout(spacing: DesignTokens.Spacing.sm) {
            ForEach(coachService.suggestedQuestions, id: \.self) { question in
                Button {
                    HapticService.shared.tap()
                    Task { await coachService.send(message: question) }
                } label: {
                    Text(question)
                        .font(DesignTokens.Typography.subheadline.weight(.medium))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.smPlus)
                        .frame(minHeight: DesignTokens.TouchTarget.minimum)
                        .glassCapsuleSurface(interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
        .glassContainer(spacing: DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var streamingMessageView: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(DesignTokens.Typography.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.accent)
                .frame(width: DesignTokens.IconSize.sm, height: DesignTokens.IconSize.sm)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                if coachService.currentStreamedContent.isEmpty {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.localized("Thinking...", comment: "AI Coach thinking state"))
                            .font(DesignTokens.Typography.subheadline)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                } else if coachService.currentStreamedContent.count <= CoachService.maxLiveMarkdownChars {
                    Text(coachService.currentStreamedRenderedContent)
                } else {
                    Text(coachService.currentStreamedContent)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
            }

            Spacer()
        }
        .padding(DesignTokens.Spacing.md)
        .calmCard(cornerRadius: DesignTokens.CornerRadius.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composerFooter: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.sm) {
                TextField(L10n.localized("Ask your coach...", comment: "AI Coach input placeholder"), text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.body)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit(sendMessage)
                    .padding(.vertical, DesignTokens.Spacing.xsPlus)
                    .padding(.leading, DesignTokens.Spacing.sm)
                    .accessibilityLabel(L10n.localized("Message", comment: "AI Coach message input label"))
                    .accessibilityIdentifier(A11yID.AICoach.input)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? DesignTokens.Colors.accent : DesignTokens.Colors.textTertiary)
                        .frame(width: DesignTokens.IconSize.touchTarget, height: DesignTokens.IconSize.touchTarget)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel(L10n.localized("Send Message", comment: "AI Coach send button accessibility label"))
                .accessibilityIdentifier(A11yID.AICoach.sendButton)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .glassCard(cornerRadius: DesignTokens.CornerRadius.xxl)

            AIDisclaimerText()
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, DesignTokens.Spacing.mdPlus)
        .padding(.top, DesignTokens.Spacing.xs)
        .padding(.bottom, DesignTokens.Spacing.sm)
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
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.Colors.warning)
                .accessibilityHidden(true)

            Text(error.localizedDescription)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Spacer()

            if canRetryLastMessage && !coachService.isGenerating {
                Button(L10n.localized("Try Again", comment: "Retry button")) {
                    Task { await coachService.retryLastMessage() }
                }
                .glassSecondaryButton()
                .controlSize(.small)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .calmCard(cornerRadius: DesignTokens.CornerRadius.lg)
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
        let now = Date.now
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
                    .font(DesignTokens.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.accent)
                    .frame(width: DesignTokens.IconSize.sm, height: DesignTokens.IconSize.sm)
                    .accessibilityHidden(true)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: DesignTokens.Spacing.xxs) {
                Group { messageContent }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.smPlus)
                    .background(
                        isUser
                            ? AnyShapeStyle(DesignTokens.Colors.accent)
                            : AnyShapeStyle(DesignTokens.Colors.surfaceElevated),
                        in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.lg, style: .continuous)
                    )
                    .overlay {
                        if !isUser {
                            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.lg, style: .continuous)
                                .strokeBorder(DesignTokens.Colors.borderMuted.opacity(0.45), lineWidth: 0.75)
                        }
                    }

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
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.onAccent)
        } else if let rendered = message.renderedContent {
            Text(rendered)
        } else {
            Text(message.content)
                .font(DesignTokens.Typography.body)
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
            true
        case let (.modelUnavailable(leftReason), .modelUnavailable(rightReason)):
            leftReason == rightReason
        case (.generationFailed, .generationFailed):
            true
        case (.tokenLimitExceeded, .tokenLimitExceeded):
            true
        case (.guardrailViolation, .guardrailViolation):
            true
        case (.invalidResponse, .invalidResponse):
            true
        default:
            false
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: result.childProposal)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint], childProposal: ProposedViewSize) {
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

        return (CGSize(width: maxX, height: currentY + lineHeight), positions, childProposal)
    }
}

#Preview {
    @MainActor in
    let fmService = FoundationModelsService()
    let demoModeStore = DemoModeStore()
    let healthKitService = HealthKitServiceFallback(demoModeStore: demoModeStore)
    return NavigationStack {
        AICoachView()
    }
    .environment(CoachService(
        foundationModelsService: fmService,
        healthKitService: healthKitService,
        goalService: GoalService(persistence: PersistenceController.shared)
    ))
    .environment(fmService)
    .environment(demoModeStore)
}
