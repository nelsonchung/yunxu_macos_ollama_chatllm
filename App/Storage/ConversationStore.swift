import Foundation

actor ConversationStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseDirectoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.baseDirectoryURL = appSupport
            .appendingPathComponent("YunxuOllamaChat", isDirectory: true)
            .appendingPathComponent("Conversations", isDirectory: true)
    }

    func loadConversations() throws -> [ChatConversation] {
        try ensureDirectories()

        let indexURL = baseDirectoryURL.appendingPathComponent("conversation-index.json")
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return []
        }

        let indexData = try Data(contentsOf: indexURL)
        let entries = try decoder.decode([ConversationIndexEntry].self, from: indexData)

        var conversations: [ChatConversation] = []
        for entry in entries {
            let fileURL = conversationFileURL(for: entry.id)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                continue
            }

            let data = try Data(contentsOf: fileURL)
            let conversation = try decoder.decode(ChatConversation.self, from: data)
            conversations.append(conversation)
        }

        return conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveConversations(_ conversations: [ChatConversation]) throws {
        try ensureDirectories()

        let sortedConversations = conversations.sorted { $0.updatedAt > $1.updatedAt }

        for conversation in sortedConversations {
            let data = try encoder.encode(conversation)
            try data.write(to: conversationFileURL(for: conversation.id), options: .atomic)
        }

        let expectedNames = Set(sortedConversations.map { "\($0.id.uuidString).json" })
        let existingFiles = try fileManager.contentsOfDirectory(atPath: baseDirectoryURL.path)
        for filename in existingFiles where filename.hasSuffix(".json") && filename != "conversation-index.json" {
            if !expectedNames.contains(filename) {
                let fileURL = baseDirectoryURL.appendingPathComponent(filename)
                try? fileManager.removeItem(at: fileURL)
            }
        }

        let indexEntries = sortedConversations.map {
            ConversationIndexEntry(id: $0.id, title: $0.title, updatedAt: $0.updatedAt)
        }
        let indexData = try encoder.encode(indexEntries)
        let indexURL = baseDirectoryURL.appendingPathComponent("conversation-index.json")
        try indexData.write(to: indexURL, options: .atomic)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    }

    private func conversationFileURL(for id: UUID) -> URL {
        baseDirectoryURL.appendingPathComponent("\(id.uuidString).json")
    }
}
