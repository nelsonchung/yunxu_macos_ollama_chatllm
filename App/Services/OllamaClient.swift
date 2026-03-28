import Foundation

actor OllamaClient {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func healthCheck(baseURL: URL) async throws {
        _ = try await fetchTags(baseURL: baseURL)
    }

    func fetchTags(baseURL: URL) async throws -> [OllamaModelTag] {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "/api/tags",
            method: "GET"
        )
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return decoded.models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchRunningModels(baseURL: URL) async throws -> [OllamaRunningModel] {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "/api/ps",
            method: "GET"
        )
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .customISO8601WithFractionalSeconds
        let decoded = try decoder.decode(OllamaRunningModelsResponse.self, from: data)
        return decoded.models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func prewarmModel(baseURL: URL, model: String) async throws {
        try await updateModelLifecycle(
            baseURL: baseURL,
            requestBody: OllamaGenerateLifecycleRequest(model: model, prompt: "", stream: false, keepAlive: .keepLoaded)
        )
    }

    func unloadModel(baseURL: URL, model: String) async throws {
        try await updateModelLifecycle(
            baseURL: baseURL,
            requestBody: OllamaGenerateLifecycleRequest(model: model, prompt: "", stream: false, keepAlive: .unloadNow)
        )
    }

    func streamChat(
        baseURL: URL,
        model: String,
        messages: [OllamaChatRequestMessage],
        settings: AppSettings,
        onChunk: @escaping @Sendable (OllamaChatChunkDelta) -> Void
    ) async throws {
        let payload = OllamaChatRequest(
            model: model,
            messages: messages,
            stream: settings.streamEnabled,
            think: settings.usesThinkingAPI ? !settings.disableThinkingForQwen : nil,
            options: OllamaChatOptions(
                temperature: settings.temperature,
                numCtx: settings.numCtx
            )
        )

        let request = try makeRequest(
            baseURL: baseURL,
            path: "/api/chat",
            method: "POST",
            body: try JSONEncoder().encode(payload)
        )

        let streamProgress = StreamProgress()
        let streamTask = Task {
            let (bytes, response) = try await urlSession.bytes(for: request)
            try validate(response: response, data: nil)

            for try await line in bytes.lines {
                if Task.isCancelled {
                    throw CancellationError()
                }

                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    continue
                }

                let chunkData = Data(trimmed.utf8)
                let chunk = try JSONDecoder().decode(OllamaChatStreamChunk.self, from: chunkData)
                let content = chunk.message?.content?.nilIfEmpty
                let thinking = chunk.message?.thinking?.nilIfEmpty
                if content != nil || thinking != nil {
                    await streamProgress.markReceivedFirstToken()
                    onChunk(OllamaChatChunkDelta(content: content, thinking: thinking))
                }

                if chunk.done {
                    return
                }
            }
        }

        let watchdogTask = Task {
            guard settings.firstTokenTimeoutSeconds > 0 else {
                return
            }

            try await Task.sleep(for: .seconds(settings.firstTokenTimeoutSeconds))
            let hasReceivedToken = await streamProgress.hasReceivedFirstToken()
            if !hasReceivedToken {
                streamTask.cancel()
            }
        }

        defer {
            watchdogTask.cancel()
        }

        do {
            try await streamTask.value
        } catch is CancellationError {
            let hasReceivedToken = await streamProgress.hasReceivedFirstToken()
            if !hasReceivedToken {
                throw OllamaClientError.firstTokenTimeout(settings.firstTokenTimeoutSeconds)
            }
            throw CancellationError()
        }
    }

    private func makeRequest(
        baseURL: URL,
        path: String,
        method: String,
        body: Data? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw OllamaClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func validate(response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let data, let errorResponse = try? JSONDecoder().decode(OllamaErrorResponse.self, from: data) {
                throw OllamaClientError.serverError(errorResponse.error)
            }

            throw OllamaClientError.httpStatus(httpResponse.statusCode)
        }
    }

    private func updateModelLifecycle(
        baseURL: URL,
        requestBody: OllamaGenerateLifecycleRequest
    ) async throws {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "/api/generate",
            method: "POST",
            body: try JSONEncoder().encode(requestBody)
        )
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
    }
}

struct OllamaChatRequestMessage: Codable, Equatable {
    let role: String
    let content: String
    let images: [String]?
}

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModelTag]
}

private struct OllamaGenerateLifecycleRequest: Codable {
    enum KeepAliveValue: Codable {
        case seconds(Int)

        static let keepLoaded = KeepAliveValue.seconds(-1)
        static let unloadNow = KeepAliveValue.seconds(0)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .seconds(let value):
                try container.encode(value)
            }
        }
    }

    let model: String
    let prompt: String
    let stream: Bool
    let keepAlive: KeepAliveValue

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case stream
        case keepAlive = "keep_alive"
    }
}

private struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaChatRequestMessage]
    let stream: Bool
    let think: Bool?
    let options: OllamaChatOptions
}

private struct OllamaChatOptions: Codable {
    let temperature: Double
    let numCtx: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case numCtx = "num_ctx"
    }
}

private struct OllamaChatStreamChunk: Decodable {
    let message: OllamaChunkMessage?
    let done: Bool
}

private struct OllamaChunkMessage: Decodable {
    let role: String?
    let content: String?
    let thinking: String?
}

struct OllamaChatChunkDelta {
    let content: String?
    let thinking: String?
}

private struct OllamaErrorResponse: Decodable {
    let error: String
}

enum OllamaClientError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case httpStatus(Int)
    case serverError(String)
    case firstTokenTimeout(Int)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The Ollama base URL is invalid."
        case .invalidResponse:
            return "The Ollama service returned an invalid response."
        case .httpStatus(let code):
            return "The Ollama service returned HTTP \(code)."
        case .serverError(let message):
            return message
        case .firstTokenTimeout(let seconds):
            return "The model did not produce any output within \(seconds) seconds."
        }
    }
}

private actor StreamProgress {
    private var receivedFirstToken = false

    func markReceivedFirstToken() {
        receivedFirstToken = true
    }

    func hasReceivedFirstToken() -> Bool {
        receivedFirstToken
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension JSONDecoder.DateDecodingStrategy {
    static let customISO8601WithFractionalSeconds = custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]

        if let date = fractionalFormatter.date(from: value)
            ?? standardFormatter.date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid ISO8601 date: \(value)"
        )
    }
}
