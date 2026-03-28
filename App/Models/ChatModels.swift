import Foundation

enum ChatRole: String, Codable, CaseIterable {
    case system
    case user
    case assistant
}

enum ChatMessageStatus: String, Codable {
    case complete
    case streaming
    case cancelled
    case error
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID
    var role: ChatRole
    var content: String
    var createdAt: Date
    var status: ChatMessageStatus

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        createdAt: Date = .now,
        status: ChatMessageStatus = .complete
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.status = status
    }
}

struct ChatConversation: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date
    var modelName: String

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [ChatMessage] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        modelName: String = AppSettings.default.selectedModel
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelName = modelName
    }
}

struct ConversationIndexEntry: Codable {
    var id: UUID
    var title: String
    var updatedAt: Date
}

enum OllamaConnectionStatus: Equatable {
    case unknown
    case checking
    case connected
    case disconnected(String)

    var label: String {
        switch self {
        case .unknown:
            return "Idle"
        case .checking:
            return "Checking"
        case .connected:
            return "Connected"
        case .disconnected:
            return "Offline"
        }
    }
}

struct OllamaModelTag: Decodable, Identifiable, Equatable {
    var id: String { name }
    let name: String
}
