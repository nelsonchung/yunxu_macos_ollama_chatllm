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

        let conversationID = updatedConversation.id
        let assistantMessageID = assistantMessage.id
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
                ) { chunk in
                    Task { @MainActor [weak self] in
                        self?.appendChunk(chunk, conversationID: conversationID, assistantMessageID: assistantMessageID)
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

    private func appendChunk(_ chunk: String, conversationID: UUID, assistantMessageID: UUID) {
        guard var conversation = conversationsViewModel.conversation(for: conversationID) else {
            return
        }

        guard let index = conversation.messages.firstIndex(where: { $0.id == assistantMessageID }) else {
            return
        }

        conversation.messages[index].content += chunk
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

        conversation.messages[index].status = status
        conversation.messages[index].completedAt = .now

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
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(20)

        var requestMessages: [OllamaChatRequestMessage] = []
        let systemPrompt = settingsViewModel.settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !systemPrompt.isEmpty {
            requestMessages.append(OllamaChatRequestMessage(role: ChatRole.system.rawValue, content: systemPrompt))
        }

        requestMessages.append(
            contentsOf: visibleMessages.map {
                OllamaChatRequestMessage(role: $0.role.rawValue, content: $0.content)
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
        let message = error.localizedDescription
        if message.contains("Could not connect") || message.contains("offline") {
            return "無法連線到本機 Ollama 服務，請確認服務是否已啟動。"
        }
        if message.localizedCaseInsensitiveContains("not found") {
            return "找不到目前選擇的模型，請確認模型名稱是否正確。"
        }
        return message
    }
}
