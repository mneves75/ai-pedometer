import SwiftUI

struct AICoachView: View {
    @Environment(CoachService.self) private var coachService
    @Environment(FoundationModelsService.self) private var aiService

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        coachContent
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "AI Coach", comment: "AI Coach navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !coachService.messages.isEmpty {
                        Button(String(localized: "Clear", comment: "Clear conversation button")) {
                            coachService.clearConversation()
                        }
                        .font(.subheadline)
                    }
                }
            }
    }

    private var coachContent: some View {
        VStack(spacing: 0) {
            if case .unavailable(let reason) = aiService.availability {
                AIAvailabilityBanner(reason: reason)
                    .padding(DesignTokens.Spacing.md)
            }

            messagesScrollView

            if aiService.availability.isAvailable {
                inputSection
            }
        }
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
                    }

                    if coachService.isGenerating {
                        streamingMessageView
                            .id("streaming")
                    }
                }
                .padding(DesignTokens.Spacing.md)
            }
            .onChange(of: coachService.messages.count) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: coachService.currentStreamedContent) { _, _ in
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
    }

    private var welcomeSection: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.purple)
                .applyIfNotUITesting { view in
                    view.symbolEffect(.pulse, options: .repeating.speed(0.5))
                }

            VStack(spacing: DesignTokens.Spacing.sm) {
                Text(String(localized: "Hi, I'm your AI Coach!", comment: "AI Coach welcome greeting"))
                    .font(.title2.bold())

                Text(String(localized: "Ask me anything about your fitness progress, goals, or get personalized recommendations.", comment: "AI Coach welcome description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            suggestedQuestionsSection
        }
        .padding(.vertical, DesignTokens.Spacing.xl)
    }

    private var suggestedQuestionsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(String(localized: "Try asking:", comment: "Label for suggested questions"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: DesignTokens.Spacing.sm) {
                ForEach(coachService.suggestedQuestions, id: \.self) { question in
                    Button {
                        Task { await coachService.send(message: question) }
                    } label: {
                        Text(question)
                            .font(.subheadline)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.vertical, DesignTokens.Spacing.sm)
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
                .font(.caption)
                .foregroundStyle(.purple)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                if coachService.currentStreamedContent.isEmpty {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "Thinking...", comment: "AI Coach thinking state"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(coachService.currentStreamedContent)
                        .font(.subheadline)
                }
            }

            Spacer()
        }
        .padding(DesignTokens.Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputSection: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: DesignTokens.Spacing.sm) {
                TextField(String(localized: "Ask your coach...", comment: "AI Coach input placeholder"), text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit(sendMessage)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? .blue : .gray)
                }
                .disabled(!canSend)
            }
            .padding(DesignTokens.Spacing.md)
            .background(.bar)
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !coachService.isGenerating
    }

    private func sendMessage() {
        guard canSend else { return }
        let message = inputText
        inputText = ""
        Task {
            await coachService.send(message: message)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(DesignTokens.Animation.smooth) {
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
            if isUser { Spacer(minLength: 40) }

            if !isUser {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(message.content)
                    .font(.subheadline)
                    .foregroundStyle(isUser ? .white : .primary)
                    .padding(DesignTokens.Spacing.md)
                    .background(
                        isUser ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.ultraThinMaterial),
                        in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md)
                    )

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !isUser { Spacer(minLength: 40) }
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
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

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
}
