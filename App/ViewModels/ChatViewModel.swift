import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var draftText = ""
    @Published var isGenerating = false
    @Published var errorMessage: String?

    private let ollamaClient: OllamaClient
    private let conversationStore: ConversationStore
    private unowned let conversationsViewModel: ConversationListViewModel
    private unowned let settingsViewModel: SettingsViewModel
    private var streamTask: Task<Void, Never>?
    private var streamParsers: [UUID: ThinkTagStreamParser] = [:]
    private var hasBootstrapped = false

    init(
        ollamaClient: OllamaClient,
        conversationStore: ConversationStore,
        conversationsViewModel: ConversationListViewModel,
        settingsViewModel: SettingsViewModel
    ) {
        self.ollamaClient = ollamaClient
        self.conversationStore = conversationStore
        self.conversationsViewModel = conversationsViewModel
        self.settingsViewModel = settingsViewModel
    }

    func bootstrap() async {
        guard !hasBootstrapped else {
            return
        }
        hasBootstrapped = true

        await settingsViewModel.load()
        await conversationsViewModel.load()
        conversationsViewModel.ensureConversationExists(defaultModel: settingsViewModel.settings.selectedModel)
        await settingsViewModel.refreshModels()
    }

    func sendMessage() {
        let trimmedText = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        guard !isGenerating else {
            return
        }

        guard let conversation = conversationsViewModel.selectedConversation else {
            errorMessage = "No conversation selected."
            return
        }

        guard let baseURL = settingsViewModel.settings.baseURL else {
            errorMessage = "請先確認 Ollama Base URL。"
            return
        }

        errorMessage = nil
        let userMessage = ChatMessage(role: .user, content: trimmedText)
        let assistantMessage = ChatMessage(role: .assistant, content: "", status: .streaming)

        var updatedConversation = conversation
        updatedConversation.modelName = settingsViewModel.settings.selectedModel
        updatedConversation.messages.append(userMessage)
        updatedConversation.messages.append(assistantMessage)
        updatedConversation.updatedAt = .now

        if updatedConversation.title == "New Chat" {
            updatedConversation.title = makeConversationTitle(from: trimmedText)
        }

        conversationsViewModel.updateConversation(updatedConversation)
        draftText = ""
        isGenerating = true
        Task {
            await settingsViewModel.refreshRunningModels()
        }

        let conversationID = updatedConversation.id
        let assistantMessageID = assistantMessage.id
        streamParsers[assistantMessageID] = ThinkTagStreamParser()
        let requestMessages = buildRequestMessages(from: updatedConversation)
        let selectedModel = settingsViewModel.settings.selectedModel
        let settingsSnapshot = settingsViewModel.settings

        streamTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await self.ollamaClient.streamChat(
                    baseURL: baseURL,
                    model: selectedModel,
                    messages: requestMessages,
                    settings: settingsSnapshot
                ) { delta in
                    Task { @MainActor [weak self] in
                        self?.appendChunk(delta, conversationID: conversationID, assistantMessageID: assistantMessageID)
                    }
                }

                self.finishAssistantMessage(
                    conversationID: conversationID,
                    assistantMessageID: assistantMessageID,
                    status: .complete
                )
            } catch is CancellationError {
                self.finishAssistantMessage(
                    conversationID: conversationID,
                    assistantMessageID: assistantMessageID,
                    status: .cancelled
                )
            } catch {
                self.errorMessage = self.presentableError(error)
                self.finishAssistantMessage(
                    conversationID: conversationID,
                    assistantMessageID: assistantMessageID,
                    status: .error
                )
            }

            self.isGenerating = false
            self.streamTask = nil
            Task {
                await self.settingsViewModel.refreshRunningModels()
            }
        }
    }

    func cancelGeneration() {
        streamTask?.cancel()
    }

    func retryConnectionCheck() {
        Task {
            await settingsViewModel.refreshModels()
        }
    }

    func persistCurrentState() {
        let conversations = conversationsViewModel.conversations
        Task {
            try? await conversationStore.saveConversations(conversations)
        }
    }

    private func appendChunk(
        _ delta: OllamaChatChunkDelta,
        conversationID: UUID,
        assistantMessageID: UUID
    ) {
        guard var conversation = conversationsViewModel.conversation(for: conversationID) else {
            return
        }

        guard let index = conversation.messages.firstIndex(where: { $0.id == assistantMessageID }) else {
            return
        }

        if let thinking = delta.thinking {
            let existingThinking = conversation.messages[index].thinking ?? ""
            conversation.messages[index].thinking = existingThinking + thinking
        }

        if let content = delta.content {
            let sanitizedContent = sanitizeThinkBoundary(
                content,
                existingThinking: conversation.messages[index].thinking
            )

            var parser = streamParsers[assistantMessageID] ?? ThinkTagStreamParser()
            let parsed = parser.consume(sanitizedContent)
            streamParsers[assistantMessageID] = parser

            if !parsed.thinking.isEmpty {
                let existingThinking = conversation.messages[index].thinking ?? ""
                conversation.messages[index].thinking = existingThinking + parsed.thinking
            }

            if !parsed.content.isEmpty {
                conversation.messages[index].content += parsed.content
            }
        }

        conversation.updatedAt = .now
        conversationsViewModel.updateConversation(conversation)
    }

    private func finishAssistantMessage(
        conversationID: UUID,
        assistantMessageID: UUID,
        status: ChatMessageStatus
    ) {
        guard var conversation = conversationsViewModel.conversation(for: conversationID) else {
            return
        }

        guard let index = conversation.messages.firstIndex(where: { $0.id == assistantMessageID }) else {
            return
        }

        if var parser = streamParsers.removeValue(forKey: assistantMessageID) {
            let trailing = parser.finish()
            if !trailing.thinking.isEmpty {
                let existingThinking = conversation.messages[index].thinking ?? ""
                conversation.messages[index].thinking = existingThinking + trailing.thinking
            }
            if !trailing.content.isEmpty {
                conversation.messages[index].content += trailing.content
            }
        }

        conversation.messages[index].status = status
        conversation.messages[index].completedAt = .now

        let normalized = conversation.messages[index].resolvedDisplay
        conversation.messages[index].content = normalized.answer
        conversation.messages[index].thinking = normalized.thinking

        if conversation.messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch status {
            case .cancelled:
                conversation.messages[index].content = "Generation cancelled."
            case .error:
                conversation.messages[index].content = "The response could not be completed."
            case .streaming, .complete:
                break
            }
        }

        conversation.updatedAt = .now
        conversationsViewModel.updateConversation(conversation)
    }

    private func buildRequestMessages(from conversation: ChatConversation) -> [OllamaChatRequestMessage] {
        let visibleMessages = conversation.messages
            .filter {
                let answer = $0.resolvedDisplay.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                return !answer.isEmpty
            }
            .suffix(20)

        var requestMessages: [OllamaChatRequestMessage] = []
        let systemPrompt = effectiveSystemPrompt()
        if !systemPrompt.isEmpty {
            requestMessages.append(OllamaChatRequestMessage(role: ChatRole.system.rawValue, content: systemPrompt))
        }

        requestMessages.append(
            contentsOf: visibleMessages.map {
                OllamaChatRequestMessage(role: $0.role.rawValue, content: $0.resolvedDisplay.answer)
            }
        )

        return requestMessages
    }

    private func makeConversationTitle(from text: String) -> String {
        let sanitized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitized.count <= 36 {
            return sanitized
        }

        let index = sanitized.index(sanitized.startIndex, offsetBy: 36)
        return "\(sanitized[..<index])..."
    }

    private func presentableError(_ error: Error) -> String {
        if case let OllamaClientError.firstTokenTimeout(seconds) = error {
            if settingsViewModel.settings.supportsThinkingToggle {
                return "模型在 \(seconds) 秒內沒有開始輸出內容。若你要保留 reasoning trace，建議把 First Token Timeout 調高；若只想更快回覆，可開啟 Quick Response Mode。"
            }
            return "模型在 \(seconds) 秒內沒有開始輸出內容，建議降低 context window 或改用更小的模型。"
        }

        let message = error.localizedDescription
        if message.contains("Could not connect") || message.contains("offline") {
            return "無法連線到本機 Ollama 服務，請確認服務是否已啟動。"
        }
        if message.localizedCaseInsensitiveContains("not found") {
            return "找不到目前選擇的模型，請確認模型名稱是否正確。"
        }
        return message
    }

    private func effectiveSystemPrompt() -> String {
        settingsViewModel.settings.systemPrompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeThinkBoundary(_ content: String, existingThinking: String?) -> String {
        guard existingThinking?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return content
        }

        var sanitized = content
        let patterns = ["</think>", "<think>"]
        for pattern in patterns {
            while true {
                let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix(pattern) else {
                    break
                }

                if let range = sanitized.range(of: pattern) {
                    sanitized.removeSubrange(range)
                } else {
                    break
                }
            }
        }

        return sanitized
    }
}
