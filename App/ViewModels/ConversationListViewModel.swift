import Foundation

@MainActor
final class ConversationListViewModel: ObservableObject {
    @Published private(set) var conversations: [ChatConversation] = []
    @Published var selectedConversationID: UUID?
    @Published var errorMessage: String?

    private let store: ConversationStore

    init(store: ConversationStore) {
        self.store = store
    }

    var selectedConversation: ChatConversation? {
        guard let selectedConversationID else {
            return conversations.first
        }
        return conversations.first(where: { $0.id == selectedConversationID })
    }

    func load() async {
        do {
            conversations = try await store.loadConversations()
            selectedConversationID = conversations.first?.id
        } catch {
            errorMessage = "Failed to load conversations: \(error.localizedDescription)"
        }
    }

    func ensureConversationExists(defaultModel: String) {
        if conversations.isEmpty {
            createConversation(defaultModel: defaultModel)
        } else if selectedConversationID == nil {
            selectedConversationID = conversations.first?.id
        }
    }

    func createConversation(defaultModel: String) {
        let conversation = ChatConversation(modelName: defaultModel)
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        persist()
    }

    func deleteConversations(at offsets: IndexSet, fallbackModel: String) {
        let idsToDelete = offsets.map { conversations[$0].id }
        deleteConversations(idsToDelete, fallbackModel: fallbackModel)
    }

    func deleteConversations(_ ids: [UUID], fallbackModel: String) {
        conversations.removeAll { ids.contains($0.id) }

        if let selectedConversationID, ids.contains(selectedConversationID) {
            self.selectedConversationID = conversations.first?.id
        }

        ensureConversationExists(defaultModel: fallbackModel)
        persist()
    }

    func updateConversation(_ conversation: ChatConversation) {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else {
            return
        }

        conversations[index] = conversation
        conversations.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func conversation(for id: UUID) -> ChatConversation? {
        conversations.first(where: { $0.id == id })
    }

    private func persist() {
        let snapshot = conversations
        Task {
            do {
                try await store.saveConversations(snapshot)
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to save conversations: \(error.localizedDescription)"
                }
            }
        }
    }
}
