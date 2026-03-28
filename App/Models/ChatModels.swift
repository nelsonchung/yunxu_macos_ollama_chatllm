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
    var thinking: String?
    var images: [ChatImageAttachment]
    var createdAt: Date
    var completedAt: Date?
    var status: ChatMessageStatus

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        thinking: String? = nil,
        images: [ChatImageAttachment] = [],
        createdAt: Date = .now,
        completedAt: Date? = nil,
        status: ChatMessageStatus = .complete
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinking = thinking
        self.images = images
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.status = status
    }

    var responseDuration: TimeInterval? {
        guard role == .assistant, let completedAt else {
            return nil
        }

        return completedAt.timeIntervalSince(createdAt)
    }

    var resolvedDisplay: ChatMessageDisplay {
        ChatMessageDisplay.from(message: self)
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

struct ChatImageAttachment: Identifiable, Codable, Equatable {
    var id: UUID
    var data: Data
    var mimeType: String
    var filename: String?

    init(
        id: UUID = UUID(),
        data: Data,
        mimeType: String = "image/png",
        filename: String? = nil
    ) {
        self.id = id
        self.data = data
        self.mimeType = mimeType
        self.filename = filename
    }

    var base64String: String {
        data.base64EncodedString()
    }
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

struct OllamaRunningModelsResponse: Decodable {
    let models: [OllamaRunningModel]
}

struct OllamaRunningModel: Decodable, Identifiable, Equatable {
    let name: String
    let model: String
    let size: Int64
    let digest: String
    let details: OllamaRunningModelDetails
    let expiresAt: Date
    let sizeVRAM: Int64
    let contextLength: Int

    var id: String { digest }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var vramLabel: String {
        ByteCountFormatter.string(fromByteCount: sizeVRAM, countStyle: .file)
    }

    var processorLabel: String {
        guard size > 0 else {
            return "CPU"
        }

        let ratio = max(0, min(Double(sizeVRAM) / Double(size), 1))
        if ratio >= 0.99 {
            return "100% GPU"
        }
        if ratio <= 0.01 {
            return "CPU"
        }
        return "\(Int((ratio * 100).rounded()))% GPU"
    }

    var summaryLabel: String {
        [details.parameterSize, details.quantizationLevel]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    enum CodingKeys: String, CodingKey {
        case name
        case model
        case size
        case digest
        case details
        case expiresAt = "expires_at"
        case sizeVRAM = "size_vram"
        case contextLength = "context_length"
    }
}

struct OllamaRunningModelDetails: Decodable, Equatable {
    let parentModel: String
    let format: String
    let family: String
    let families: [String]
    let parameterSize: String
    let quantizationLevel: String

    enum CodingKeys: String, CodingKey {
        case parentModel = "parent_model"
        case format
        case family
        case families
        case parameterSize = "parameter_size"
        case quantizationLevel = "quantization_level"
    }
}

struct ContextUsageSnapshot: Equatable {
    let messageCount: Int
    let characterCount: Int
    let estimatedTokenCount: Int
    let contextWindow: Int

    var utilizationRatio: Double {
        guard contextWindow > 0 else {
            return 0
        }
        return min(Double(estimatedTokenCount) / Double(contextWindow), 1)
    }

    var remainingTokenEstimate: Int {
        max(contextWindow - estimatedTokenCount, 0)
    }
}

struct ChatMessageDisplay: Equatable {
    let answer: String
    let thinking: String?

    static func from(message: ChatMessage) -> ChatMessageDisplay {
        let existingThinking = message.thinking?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existingThinking, !existingThinking.isEmpty {
            return ChatMessageDisplay(answer: message.content, thinking: message.thinking)
        }

        if !message.content.contains(ThinkTagStreamParser.openTag),
           let closeRange = message.content.range(of: ThinkTagStreamParser.closeTag) {
            let thinking = String(message.content[..<closeRange.lowerBound]).nilIfBlank
            let answer = String(message.content[closeRange.upperBound...])
            return ChatMessageDisplay(answer: answer, thinking: thinking)
        }

        let parsed = ThinkTagStreamParser.parse(message.content)
        return ChatMessageDisplay(
            answer: parsed.content,
            thinking: parsed.thinking.nilIfBlank
        )
    }
}

struct ThinkTagStreamOutput: Equatable {
    let content: String
    let thinking: String
}

struct ThinkTagStreamParser: Equatable {
    private enum Mode: Equatable {
        case answer
        case thinking
    }

    static let openTag = "<think>"
    static let closeTag = "</think>"

    private var mode: Mode = .answer
    private var pending = ""

    mutating func consume(_ chunk: String) -> ThinkTagStreamOutput {
        pending += chunk
        return drain(flushAll: false)
    }

    mutating func finish() -> ThinkTagStreamOutput {
        drain(flushAll: true)
    }

    static func parse(_ text: String) -> ThinkTagStreamOutput {
        var parser = ThinkTagStreamParser()
        let partial = parser.consume(text)
        let final = parser.finish()
        return ThinkTagStreamOutput(
            content: partial.content + final.content,
            thinking: partial.thinking + final.thinking
        )
    }

    private mutating func drain(flushAll: Bool) -> ThinkTagStreamOutput {
        var contentOutput = ""
        var thinkingOutput = ""

        while !pending.isEmpty {
            switch mode {
            case .answer:
                if let range = pending.range(of: Self.openTag) {
                    contentOutput += String(pending[..<range.lowerBound])
                    pending.removeSubrange(..<range.upperBound)
                    mode = .thinking
                    continue
                }

                let flushCount = flushAll ? pending.count : pending.count - pending.trailingPrefixOverlap(with: Self.openTag)
                guard flushCount > 0 else {
                    return ThinkTagStreamOutput(content: contentOutput, thinking: thinkingOutput)
                }

                let index = pending.index(pending.startIndex, offsetBy: flushCount)
                contentOutput += String(pending[..<index])
                pending.removeSubrange(..<index)

            case .thinking:
                if let range = pending.range(of: Self.closeTag) {
                    thinkingOutput += String(pending[..<range.lowerBound])
                    pending.removeSubrange(..<range.upperBound)
                    mode = .answer
                    continue
                }

                let flushCount = flushAll ? pending.count : pending.count - pending.trailingPrefixOverlap(with: Self.closeTag)
                guard flushCount > 0 else {
                    return ThinkTagStreamOutput(content: contentOutput, thinking: thinkingOutput)
                }

                let index = pending.index(pending.startIndex, offsetBy: flushCount)
                thinkingOutput += String(pending[..<index])
                pending.removeSubrange(..<index)
            }
        }

        return ThinkTagStreamOutput(content: contentOutput, thinking: thinkingOutput)
    }
}

private extension String {
    func trailingPrefixOverlap(with pattern: String) -> Int {
        let maxLength = min(count, pattern.count - 1)
        guard maxLength > 0 else {
            return 0
        }

        for length in stride(from: maxLength, through: 1, by: -1) {
            let suffixIndex = index(endIndex, offsetBy: -length)
            if self[suffixIndex...] == pattern.prefix(length) {
                return length
            }
        }

        return 0
    }

    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
